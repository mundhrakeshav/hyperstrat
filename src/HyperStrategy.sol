// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "solady/tokens/ERC20.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import "./HyperInterfaces.sol";
import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";

/// @title Hyyper Strategy - https://hyperstr.xyz
contract HyperStrategy is ERC20, ReentrancyGuard {
    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                  CONSTANTS                                  */
    /* ═══════════════════════════════════════════════════════════════════════════ */
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18; //1b
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                  IMMUTABLES                                  */
    /* ═══════════════════════════════════════════════════════════════════════════ */
    ISwapRouter public immutable swapRouter;
    address public immutable factory;
    IERC721 public immutable collection;

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               STATE VARIABLES                               */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    string private tokenName;
    string private tokenSymbol;
    uint256 public priceMultiplier = 1200; // 1.2x
    mapping(uint256 => uint256) public nftForSale; // tokenId => price in $HYPE
    uint256 public currentFees; // Accumulated trading fees, used to buy NFTs

    uint256 public hypeToTwap; // HYPE from NFT sales waiting to be converted to buyback
    // hypeToTwap (NFT Selling) to be burned
    uint256 public twapIncrement = 50 ether; // Amount to burn per TWAP execution
    uint256 public twapDelayInBlocks = 30; // Blocks between TWAP executions
    uint256 public lastTwapBlock; // Last block TWAP was executed

    // @audit should this be transient?
    bool public midSwap; // Flag to allow transfers during swaps
    address public feeCollector; // Address authorized to deposit fees
    mapping(address => bool) public whitelistedMarketplaces; // Authorized NFT marketplaces

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                CUSTOM EVENTS                                */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    event NFTBoughtByProtocol(uint256 indexed tokenId, uint256 purchasePrice, uint256 listPrice);
    event NFTSoldByProtocol(uint256 indexed tokenId, uint256 price, address buyer);
    event FeesAdded(uint256 amount, address indexed sender);
    event TokensBurned(uint256 hypeAmount, uint256 tokensReceived);
    event TwapParametersUpdated(uint256 increment, uint256 delay);
    event MarketplaceWhitelisted(address indexed marketplace, bool status);

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                CUSTOM ERRORS                                */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    error NFTNotForSale();
    error NFTPriceTooLow();
    error InvalidMultiplier();
    error NoHYPEToTwap();
    error TwapDelayNotMet();
    error NotEnoughHype();
    error NotFactory();
    error AlreadyNFTOwner();
    error NeedToBuyNFT();
    error NotNFTOwner();
    error NotFeeCollector();
    error ExternalCallFailed(bytes reason);
    error NotValidRouter();
    error InvalidAddress();
    error InvalidFactory();
    error InvalidSwapRouter();
    error InvalidCollection();
    error InvalidFeeCollector();
    error MarketplaceNotWhitelisted();

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                 CONSTRUCTOR                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Initializes the HyperStrategy contract
    /// @param _tokenName Name of the strategy token
    /// @param _tokenSymbol Symbol of the strategy token
    /// @param _factory Address of the HyperFactory contract
    /// @param _swapRouter Address of the GLiquid SwapRouter contract
    /// @param _collection Address of the NFT collection contract
    /// @param _feeCollector Address authorized to deposit trading fees
    constructor(
        string memory _tokenName,
        string memory _tokenSymbol,
        address _factory,
        ISwapRouter _swapRouter,
        address _collection,
        address _feeCollector
    ) {
        if (_factory == address(0)) {
            revert InvalidFactory();
        }

        if (address(_swapRouter) == address(0)) {
            revert InvalidSwapRouter();
        }

        if (_collection == address(0)) {
            revert InvalidCollection();
        }

        if (_feeCollector == address(0)) {
            revert InvalidFeeCollector();
        }

        factory = _factory;
        swapRouter = _swapRouter;
        collection = IERC721(_collection);
        tokenName = _tokenName;
        tokenSymbol = _tokenSymbol;
        feeCollector = _feeCollector;

        _mint(factory, MAX_SUPPLY);
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                VIEW FUNCTIONS                               */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Returns the name of the token
    function name() public view override returns (string memory) {
        return tokenName;
    }

    /// @notice Returns the symbol of the token
    function symbol() public view override returns (string memory) {
        return tokenSymbol;
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                              ADMIN FUNCTIONS                                */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Updates the name of the token
    /// @dev Can only be called by the factory
    /// @param _tokenName New name for the token
    function updateName(string memory _tokenName) external {
        if (msg.sender != factory) revert NotFactory();
        tokenName = _tokenName;
    }

    /// @notice Updates the symbol of the token
    /// @dev Can only be called by the factory
    /// @param _tokenSymbol New symbol for the token
    function updateSymbol(string memory _tokenSymbol) external {
        if (msg.sender != factory) revert NotFactory();
        tokenSymbol = _tokenSymbol;
    }

    /// @notice Updates the price multiplier for relisting NFTs
    /// @param _newMultiplier New multiplier in basis points (1100 = 1.1x, 10000 = 10.0x)
    /// @dev Only callable by factory. Must be between 1.1x (1100) and 10.0x (10000)
    function setPriceMultiplier(uint256 _newMultiplier) external {
        if (msg.sender != factory) revert NotFactory();
        if (_newMultiplier < 1100 || _newMultiplier > 10000) revert InvalidMultiplier();
        priceMultiplier = _newMultiplier;
    }

    /// @notice Updates the TWAP parameters
    /// @param _newIncrement Amount of HYPE to burn per TWAP execution
    /// @param _newDelay Blocks between TWAP executions
    /// @dev Only callable by factory
    function setTwapParameters(uint256 _newIncrement, uint256 _newDelay) external {
        if (msg.sender != factory) revert NotFactory();
        twapIncrement = _newIncrement;
        twapDelayInBlocks = _newDelay;
        emit TwapParametersUpdated(_newIncrement, _newDelay);
    }

    /// @notice Updates the fee collector address
    /// @param _newCollector New fee collector address
    /// @dev Only callable by factory
    function setFeeCollector(address _newCollector) external {
        if (msg.sender != factory) revert NotFactory();
        if (_newCollector == address(0)) revert InvalidAddress();
        feeCollector = _newCollector;
    }

    /// @notice Adds or removes a marketplace from the whitelist
    /// @param _marketplace Address of the marketplace contract
    /// @param _status True to whitelist, false to remove
    /// @dev Only callable by factory
    function setMarketplaceWhitelist(address _marketplace, bool _status) external {
        if (msg.sender != factory) revert NotFactory();
        if (_marketplace == address(0)) revert InvalidAddress();
        whitelistedMarketplaces[_marketplace] = _status;
        emit MarketplaceWhitelisted(_marketplace, _status);
    }

    // @audit Maybe have a func to remove sometyhing from the whitelist

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                            MECHANISM FUNCTIONS                              */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Allows authorized fee collector to deposit trading fees
    /// @dev Only callable by the fee collector contract/address
    function addFees() external payable nonReentrant {
        if (msg.sender != feeCollector && msg.sender != factory) revert NotFeeCollector();
        currentFees += msg.value;
        emit FeesAdded(msg.value, msg.sender);
    }

    /// @notice Sets midSwap flag to allow transfers during swaps
    /// @dev Only callable by fee collector or factory
    function setMidSwap(bool value) external {
        if (msg.sender != feeCollector && msg.sender != factory) revert NotFeeCollector();
        midSwap = value;
    }

    // @audit review this
    /// @notice Buys a specific NFT from external marketplace and lists it for sale
    /// @param value Amount of HYPE to spend on the NFT purchase
    /// @param data Calldata to execute the purchase
    /// @param expectedId Token ID expected to be purchased
    /// @param target Target contract address (marketplace)
    /// @dev Only callable by fee collector or factory
    function buyTargetNFT(uint256 value, bytes calldata data, uint256 expectedId, address target)
        external
        nonReentrant
    {
        // Only fee collector or factory can call this
        if (msg.sender != feeCollector && msg.sender != factory) {
            revert NotFeeCollector();
        }

        // Verify marketplace is whitelisted
        if (!whitelistedMarketplaces[target]) {
            revert MarketplaceNotWhitelisted();
        }

        // Store balances before external call
        uint256 hypeBalanceBefore = address(this).balance;
        uint256 nftBalanceBefore = collection.balanceOf(address(this));

        // Verify we don't already own the NFT
        if (collection.ownerOf(expectedId) == address(this)) {
            revert AlreadyNFTOwner();
        }

        // Ensure we have enough fees to cover the purchase
        if (value > currentFees) {
            revert NotEnoughHype();
        }

        // Execute purchase on external marketplace
        (bool success, bytes memory reason) = target.call{value: value}(data);
        if (!success) {
            revert ExternalCallFailed(reason);
        }

        // Verify we received exactly one more NFT
        uint256 nftBalanceAfter = collection.balanceOf(address(this));
        if (nftBalanceAfter != nftBalanceBefore + 1) {
            revert NeedToBuyNFT();
        }

        // Verify we now own the expected NFT
        if (collection.ownerOf(expectedId) != address(this)) {
            revert NotNFTOwner();
        }

        // Calculate actual cost and update fees
        uint256 cost = hypeBalanceBefore - address(this).balance;
        if (cost > currentFees) {
            revert NotEnoughHype();
        }
        currentFees -= cost;

        // List NFT for sale at markup
        uint256 salePrice = (cost * priceMultiplier) / 1000;
        nftForSale[expectedId] = salePrice;

        emit NFTBoughtByProtocol(expectedId, cost, salePrice);
    }

    /// @notice Sells an NFT owned by the contract for the listed price
    /// @param tokenId The ID of the NFT to sell
    function sellTargetNFT(uint256 tokenId) external payable nonReentrant {
        // Get sale price
        uint256 salePrice = nftForSale[tokenId];

        // Verify NFT is for sale
        if (salePrice == 0) revert NFTNotForSale();

        // Verify sent HYPE matches sale price
        if (msg.value != salePrice) revert NFTPriceTooLow();

        // Verify contract owns the NFT
        if (collection.ownerOf(tokenId) != address(this)) revert NotNFTOwner();

        // Transfer NFT to buyer
        collection.transferFrom(address(this), msg.sender, tokenId);

        // Remove NFT from sale
        delete nftForSale[tokenId];

        // Add sale proceeds to TWAP queue
        hypeToTwap += salePrice;

        emit NFTSoldByProtocol(tokenId, salePrice, msg.sender);
    }

    /// @notice Processes accumulated HYPE to buy and burn tokens via TWAP
    /// @dev Can be called by anyone once delay period has passed
    /// @dev Caller receives 0.5% reward for executing the transaction
    function processTokenTwap() external nonReentrant {
        if (hypeToTwap == 0) revert NoHYPEToTwap();

        // Check if enough blocks have passed since last TWAP
        if (block.number < lastTwapBlock + twapDelayInBlocks) revert TwapDelayNotMet();

        // Calculate amount to burn - either twapIncrement or remaining hypeToTwap
        uint256 burnAmount = twapIncrement;
        if (hypeToTwap < twapIncrement) {
            burnAmount = hypeToTwap;
        }

        // Calculate 0.5% reward for caller
        uint256 reward = (burnAmount * 5) / 1000;
        burnAmount -= reward;

        // Update state
        hypeToTwap -= (burnAmount + reward);
        lastTwapBlock = block.number;

        // Execute buy and burn
        _buyAndBurnTokens(burnAmount);

        // Send reward to caller
        SafeTransferLib.forceSafeTransferETH(msg.sender, reward);
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                             INTERNAL FUNCTIONS                              */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Buys tokens with native $HYPE via GLiquid and burns them
    /// @param amountIn The amount of $HYPE to spend on tokens
    function _buyAndBurnTokens(uint256 amountIn) internal {
        // Set midSwap to allow the transfer
        midSwap = true;

        // Prepare swap parameters - using native $HYPE
        // Note: For native token, we use address(0) as tokenIn
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(0), // Native $HYPE token
            deployer: address(0), // Standard pool, not custom
            tokenOut: address(this),
            recipient: DEAD_ADDRESS, // Send directly to burn address
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0, // No slippage protection for burns
            limitSqrtPrice: 0 // No price limit
        });

        // Execute swap with native token - tokens go directly to DEAD_ADDRESS
        uint256 amountOut = swapRouter.exactInputSingle{value: amountIn}(params);

        // Reset midSwap
        midSwap = false;

        emit TokensBurned(amountIn, amountOut);
    }

    // @audit review this: is this
    /// @notice Validates transfers based on router restrictions
    /// @param from The address sending tokens
    /// @param to The address receiving tokens
    /// @dev Reverts if transfer isn't through approved router
    function _afterTokenTransfer(address from, address to, uint256) internal view override {
        // Allow transfer if router restrictions are disabled or we're mid-swap
        if (!IHyperFactory(factory).routerRestrict() || midSwap) return;

        // Check if transfer is valid based on factory rules
        if (!IHyperFactory(factory).validTransfer(from, to, address(this))) {
            revert NotValidRouter();
        }
    }

    /// @notice ERC721 receiver function to accept NFT transfers
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(collection)) {
            revert InvalidCollection();
        }
        return this.onERC721Received.selector;
    }

    /// @notice Allows the contract to receive HYPE
    receive() external payable {}
}
