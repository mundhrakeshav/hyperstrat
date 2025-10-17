// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "solady/tokens/ERC20.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IWHYPE} from "src/interfaces/IWHYPE.sol";

contract HyperStrategy is ERC20, ReentrancyGuard, Ownable {
    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                  CONSTANTS                                  */
    /* ═══════════════════════════════════════════════════════════════════════════ */
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18; //1b
    uint256 public constant E6 = 1_000_000; // Basis points denominator (hundredth of BPS)
    address public constant DEAD_ADDRESS = address(0xdEaD);
    address public constant WHYPE = address(0x5555555555555555555555555555555555555555);
    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                  IMMUTABLES                                  */
    /* ═══════════════════════════════════════════════════════════════════════════ */
    ISwapRouter public immutable swapRouter;
    IERC721 public immutable collection;

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               STATE VARIABLES                               */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    string private tokenName;
    string private tokenSymbol;
    uint256 public priceMultiplier;
    uint256 public currentFees;

    mapping(address => bool) public whitelistedMarketplaces;
    mapping(address => mapping(bytes4 => bool)) public whitelistedSelectors;
    mapping(address => bool) public whitelistedTransferAddresses;

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                CUSTOM EVENTS                                */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    event NFTBoughtByProtocol(uint256 indexed tokenId, uint256 purchasePrice, uint256 listPrice);
    event NFTSoldByProtocol(uint256 indexed tokenId, uint256 price, address buyer);
    event FeesAdded(uint256 amt, address indexed sender);
    event TokensBurned(uint256 amt, uint256 tokensReceived);
    event MarketplaceWhitelisted(address indexed marketplace, bool status);
    event PriceMultiplierUpdated(uint256 newPriceMultiplier);
    event SelectorWhitelisted(address indexed marketplace, bytes4 indexed selector, bool status);
    event TransferAddressWhitelisted(address indexed transferAddress, bool status);
    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                CUSTOM ERRORS                                */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    error InvalidSwapRouter();
    error InvalidCollection();
    error InvalidFeeCollector();
    error InvalidAddress();
    error InvalidMultiplier();
    error PluginAlreadySet();
    error NotPlugin();
    error NotFactory();
    error NotFeeCollector();
    error NotEnoughValue();
    error AlreadyNFTOwner();
    error NeedToBuyNFT();
    error NotNFTOwner();
    error NotWhitelistedSelector();
    error MarketplaceNotWhitelisted();
    error ExternalCallFailed(bytes reason);
    error InvalidTransfer();

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                 CONSTRUCTOR                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Initializes the HyperStrategy contract
    /// @param _tokenName Name of the strategy token
    /// @param _tokenSymbol Symbol of the strategy token
    /// @param _owner Address of the owner
    /// @param _swapRouter Address of the GLiquid SwapRouter contract
    /// @param _collection Address of the NFT collection contract
    constructor(
        string memory _tokenName,
        string memory _tokenSymbol,
        address _owner,
        ISwapRouter _swapRouter,
        address _collection
    ) {
        if (address(_swapRouter) == address(0)) {
            revert InvalidSwapRouter();
        }

        if (_collection == address(0)) {
            revert InvalidCollection();
        }

        _initializeOwner(_owner);
        swapRouter = _swapRouter;
        collection = IERC721(_collection);
        tokenName = _tokenName;
        tokenSymbol = _tokenSymbol;
        priceMultiplier = 1_200_000; // Default 1.2x markup
        _mint(_owner, MAX_SUPPLY);
    }

    function _guardInitializeOwner() internal pure override returns (bool guard) {
        return true;
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

    /// @notice Updates the price multiplier for relisting NFTs
    /// @param _newMultiplier New multiplier in 1e6-scale
    /// @dev Only callable by owner
    function setPriceMultiplier(uint256 _newMultiplier) external onlyOwner {
        priceMultiplier = _newMultiplier;
        emit PriceMultiplierUpdated(_newMultiplier);
    }

    /// @notice Adds or removes a marketplace from the whitelist
    /// @param _marketplace Address of the marketplace contract
    /// @param _status True to whitelist, false to remove
    /// @dev Only callable by owner
    function setMarketplaceWhitelist(address _marketplace, bool _status) external onlyOwner {
        if (_marketplace == address(0)) revert InvalidAddress();
        whitelistedMarketplaces[_marketplace] = _status;
        emit MarketplaceWhitelisted(_marketplace, _status);
    }

    // @audit Maybe have a func to remove sometyhing from the whitelist

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                            MECHANISM FUNCTIONS                              */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    function setSelectorWhitelist(address _marketplace, bytes4 _selector, bool _status) external onlyOwner {
        if (_marketplace == address(0) || _selector == bytes4(0)) revert InvalidAddress();
        whitelistedSelectors[_marketplace][_selector] = _status;
        emit SelectorWhitelisted(_marketplace, _selector, _status);
    }

    /// @notice Adds or removes a transfer address from the whitelist
    /// @param _transferAddress Address to whitelist for transfers
    /// @param _status True to whitelist, false to remove
    /// @dev Only callable by owner
    function setTransferAddressWhitelist(address _transferAddress, bool _status) external onlyOwner {
        if (_transferAddress == address(0)) revert InvalidAddress();
        whitelistedTransferAddresses[_transferAddress] = _status;
        emit TransferAddressWhitelisted(_transferAddress, _status);
    }

    /* TODO:
        - Needs approval flow
        - Needs to be able to sell NFTs
    */
    /// @notice Buys a specific NFT from an external marketplace and lists it for sale
    /// @param marketplace marketplace contract address
    /// @param value Amount of HYPE (native) to send with the purchase call
    /// @param data Calldata to execute the purchase on the marketplace
    /// @param expectedId Token ID expected to be purchased
    /// @dev Anyone may call this function. The contract will only execute calls to
    ///      marketplaces and function selectors that are present in the contract-controlled
    ///      whitelists (see `whitelistedMarketplaces` and `whitelistedSelectors`). These
    ///      whitelists are controlled by the factory/owner. The function uses the
    ///      contract's native balance minus `currentFees` to pay for purchases.

    function buyNFT(address marketplace, uint256 value, bytes calldata data, uint256 expectedId)
        external
        nonReentrant
    {
        // Verify marketplace is whitelisted
        if (!whitelistedMarketplaces[marketplace]) {
            revert MarketplaceNotWhitelisted();
        }

        // Ensure calldata has at least 4 bytes before taking the selector slice
        if (data.length < 4 || !whitelistedSelectors[marketplace][bytes4(data[:4])]) {
            revert NotWhitelistedSelector();
        }

        // Check ownership, but don't revert if token doesn't exist (ownerOf may revert)
        try collection.ownerOf(expectedId) returns (address owner) {
            if (owner == address(this)) {
                revert AlreadyNFTOwner();
            }
        } catch {
            // If ownerOf reverts (non-existent token), proceed — caller expects to buy it
        }

        uint256 totalBalanceBefore = address(this).balance;
        uint256 nftBalanceBefore = collection.balanceOf(address(this));

        // Ensure reserved fees aren't larger than the available balance
        if (totalBalanceBefore < currentFees) {
            revert NotEnoughValue();
        }

        uint256 balanceToSpend = totalBalanceBefore - currentFees;

        if (value > balanceToSpend) {
            revert NotEnoughValue();
        }

        (bool success, bytes memory returnData) = marketplace.call{value: value}(data);
        if (!success) {
            revert ExternalCallFailed(returnData);
        }

        uint256 nftBalanceAfter = collection.balanceOf(address(this));
        if (nftBalanceAfter != nftBalanceBefore + 1) {
            revert NeedToBuyNFT();
        }

        if (collection.ownerOf(expectedId) != address(this)) {
            revert NotNFTOwner();
        }

        // Compute cost safely: if the contract balance increased (e.g. refunds/bonuses),
        // avoid underflow by setting cost to 0 in that case.
        uint256 totalBalanceAfter = address(this).balance;
        uint256 cost;
        if (totalBalanceAfter <= totalBalanceBefore) {
            uint256 diff = totalBalanceBefore - totalBalanceAfter;
            // Clamp cost to at most the `value` sent for the purchase call
            cost = diff > value ? value : diff;
        } else {
            // Received more ETH than before the call; treat purchase cost as 0
            cost = 0;
        }

        // List NFT for sale at markup
        uint256 salePrice = (cost * priceMultiplier) / E6;

        // List NFT for sale at markup
        // nftForSale[expectedId] = salePrice;
        emit NFTBoughtByProtocol(expectedId, cost, salePrice);
    }

    // /// @notice Sells an NFT owned by the contract for the listed price
    // /// @param tokenId The ID of the NFT to sell
    // function sellTargetNFT(uint256 tokenId) external payable nonReentrant {
    //     // Get sale price
    //     uint256 salePrice = nftForSale[tokenId];

    //     // Verify NFT is for sale
    //     if (salePrice == 0) revert NFTNotForSale();

    //     // Verify sent HYPE matches sale price
    //     if (msg.value != salePrice) revert NFTPriceTooLow();

    //     // Verify contract owns the NFT
    //     if (collection.ownerOf(tokenId) != address(this)) revert NotNFTOwner();

    //     // Transfer NFT to buyer
    //     collection.transferFrom(address(this), msg.sender, tokenId);

    //     // Remove NFT from sale
    //     delete nftForSale[tokenId];

    //     // Add sale proceeds to TWAP queue
    //     hypeToTwap += salePrice;

    //     emit NFTSoldByProtocol(tokenId, salePrice, msg.sender);
    // }

    // /// @notice Processes accumulated HYPE to buy and burn tokens
    // /// @dev Can be called by anyone once delay period has passed
    // /// @dev Caller receives 0.5% reward for executing the transaction
    // function buyAndBurnTokens() external nonReentrant {
    //     if (hypeToTwap == 0) revert NoHYPEToTwap();

    //     // Check if enough blocks have passed since last TWAP
    //     if (block.number < lastTwapBlock + twapDelayInBlocks) revert TwapDelayNotMet();

    //     // Calculate amount to burn - either twapIncrement or remaining hypeToTwap
    //     uint256 burnAmount = twapIncrement;
    //     if (hypeToTwap < twapIncrement) {
    //         burnAmount = hypeToTwap;
    //     }

    //     // Calculate 0.5% reward for caller
    //     uint256 reward = (burnAmount * 5) / 1000;
    //     burnAmount -= reward;

    //     // Update state
    //     hypeToTwap -= (burnAmount + reward);
    //     lastTwapBlock = block.number;

    //     // Execute buy and burn
    //     _buyAndBurnTokens(burnAmount);

    //     // Send reward to caller
    //     SafeTransferLib.forceSafeTransferETH(msg.sender, reward);
    // }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                             INTERNAL FUNCTIONS                              */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Buys tokens with native $HYPE via GLiquid and burns them
    /// @param amountIn The amount of $HYPE to spend on tokens
    function _buyAndBurnTokens(uint256 amountIn) internal {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WHYPE,
            deployer: address(0),
            tokenOut: address(this),
            recipient: DEAD_ADDRESS,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            limitSqrtPrice: 0
        });

        // Execute swap with native token - tokens go directly to DEAD_ADDRESS
        uint256 amountOut = swapRouter.exactInputSingle{value: amountIn}(params);

        emit TokensBurned(amountIn, amountOut);
    }

    // @audit review this: is this
    /// @notice Validates transfers based on router restrictions
    /// @param from The address sending tokens
    /// @param to The address receiving tokens
    /// @dev Reverts if transfer isn't through approved router
    function _afterTokenTransfer(address from, address to, uint256) internal view override {
        // Allow minting (from = address(0))
        if (from == address(0)) return;

        // Allow burning (to = DEAD_ADDRESS or address(0))
        if (to == DEAD_ADDRESS || to == address(0)) return;

        if (whitelistedTransferAddresses[from] || whitelistedTransferAddresses[to]) {
            return;
        }

        revert InvalidTransfer();
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
