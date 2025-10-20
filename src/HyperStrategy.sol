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

    mapping(address => bool) public whitelistedTargets;
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
    event TargetWhitelisted(address indexed target, bool status);
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
    /// @param _target Address of the target contract
    /// @param _status True to whitelist, false to remove
    /// @dev Only callable by owner
    function setTargetWhitelist(address _target, bool _status) external onlyOwner {
        if (_target == address(0)) revert InvalidAddress();
        whitelistedTargets[_target] = _status;
        emit TargetWhitelisted(_target, _status);
    }

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

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                            MECHANISM FUNCTIONS                              */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    function executeExternalCall(address[] calldata targets, bytes[] calldata data, uint256[] calldata values)
        external
        nonReentrant
    {
        // Ensure arrays have the same length
        if (targets.length != data.length || targets.length != values.length) {
            revert InvalidAddress();
        }

        // Loop through all targets and execute calls
        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];
            bytes calldata callData = data[i];
            uint256 value = values[i];

            // Verify target is whitelisted
            if (!whitelistedTargets[target]) {
                revert MarketplaceNotWhitelisted();
            }

            // Ensure calldata has at least 4 bytes before taking the selector slice
            if (callData.length < 4 || !whitelistedSelectors[target][bytes4(callData[:4])]) {
                revert NotWhitelistedSelector();
            }

            // Execute the external call
            (bool success, bytes memory returnData) = target.call{value: value}(callData);
            if (!success) {
                revert ExternalCallFailed(returnData);
            }
        }
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
