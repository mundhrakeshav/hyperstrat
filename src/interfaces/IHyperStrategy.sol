// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";

interface IHyperStrategy is IERC20 {
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
    /*                                VIEW FUNCTIONS                               */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Returns the name of the token
    function name() external view returns (string memory);

    /// @notice Returns the symbol of the token
    function symbol() external view returns (string memory);

    /// @notice Returns the maximum token supply
    function MAX_SUPPLY() external view returns (uint256);

    /// @notice Returns the basis points denominator
    function E6() external view returns (uint256);

    /// @notice Returns the dead address used for burning
    function DEAD_ADDRESS() external view returns (address);

    /// @notice Returns the wrapped HYPE token address
    function WHYPE() external view returns (address);

    /// @notice Returns the swap router interface
    function swapRouter() external view returns (ISwapRouter);

    /// @notice Returns the NFT collection interface
    function collection() external view returns (IERC721);

    /// @notice Returns the current price multiplier for relisting NFTs
    function priceMultiplier() external view returns (uint256);

    /// @notice Returns the current accumulated fees
    function currentFees() external view returns (uint256);

    /// @notice Checks if a marketplace is whitelisted
    /// @param marketplace Address to check
    function whitelistedMarketplaces(address marketplace) external view returns (bool);

    /// @notice Checks if a specific selector is whitelisted for a marketplace
    /// @param marketplace Marketplace address
    /// @param selector Function selector to check
    function whitelistedSelectors(address marketplace, bytes4 selector) external view returns (bool);

    /// @notice Returns the owner of the contract
    function owner() external view returns (address);

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                              ADMIN FUNCTIONS                                */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Updates the price multiplier for relisting NFTs
    /// @param _newMultiplier New multiplier in 1e6-scale
    function setPriceMultiplier(uint256 _newMultiplier) external;

    /// @notice Adds or removes a marketplace from the whitelist
    /// @param _marketplace Address of the marketplace contract
    /// @param _status True to whitelist, false to remove
    function setMarketplaceWhitelist(address _marketplace, bool _status) external;

    /// @notice Adds or removes a function selector from the whitelist for a marketplace
    /// @param _marketplace Address of the marketplace contract
    /// @param _selector Function selector to whitelist
    /// @param _status True to whitelist, false to remove
    function setSelectorWhitelist(address _marketplace, bytes4 _selector, bool _status) external;

    /// @notice Adds or removes a transfer address from the whitelist
    /// @param _transferAddress Address to whitelist for transfers
    /// @param _status True to whitelist, false to remove
    /// @dev Only callable by owner
    function setTransferAddressWhitelist(address _transferAddress, bool _status) external;

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                            MECHANISM FUNCTIONS                              */
    /* ═══════════════════════════════════════════════════════════════════════════ */
    /// @notice Buys a specific NFT from an external marketplace
    /// @param marketplace Marketplace contract address
    /// @param value Amount of HYPE (native) to send with the purchase call
    /// @param data Calldata to execute the purchase on the marketplace
    /// @param expectedId Token ID expected to be purchased
    function buyNFT(address marketplace, uint256 value, bytes calldata data, uint256 expectedId) external;

    /// @notice ERC721 receiver function to accept NFT transfers
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        view
        returns (bytes4);

    /// @notice Allows the contract to receive HYPE
    receive() external payable;
}
