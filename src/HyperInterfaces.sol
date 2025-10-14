// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ERC721 Interface
interface IERC721 {
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

/// @title Hyper Strategy Interface
interface IHyperStrategy {
    function addFees() external payable;
    function setMidSwap(bool _midSwap) external;
    function setPriceMultiplier(uint256 _newMultiplier) external;
    function updateName(string memory _tokenName) external;
    function updateSymbol(string memory _tokenSymbol) external;
    function setFeeCollector(address _newCollector) external;
    function setMarketplaceWhitelist(address _marketplace, bool _status) external;
    function collection() external view returns (address);
    function currentFees() external view returns (uint256);
    function priceMultiplier() external view returns (uint256);
    function feeCollector() external view returns (address);
    function whitelistedMarketplaces(address _marketplace) external view returns (bool);
}

/// @title HyperStrategy Factory Interface (for GLiquid version)
interface IHyperStrategyFactory {
    function owner() external view returns (address);
    function loadingLiquidity() external view returns (bool);
    function routerRestrict() external view returns (bool);
    function deployerBuying() external view returns (bool);
    function hyperStrategyToCollection(address strategy) external view returns (address);
}

/// @title Hyper Factory Interface
interface IHyperFactory {
    function owner() external view returns (address);
    function validRouter(address router) external view returns (bool);
    function routerRestrict() external view returns (bool);
    function setRouter(address router, bool status) external;
    function setRouterRestrict(bool status) external;
    function validTransfer(address from, address to, address tokenAddress) external view returns (bool);
    function collectionToStrategy(address collection) external view returns (address);
    function strategyToCollection(address strategy) external view returns (address);
}

/// @title ERC20 Interface
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title WETH9 Interface (for WHYPE)
/// @notice Interface for Wrapped HYPE token on HyperEVM
interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}