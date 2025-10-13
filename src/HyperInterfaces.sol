// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// /// @title GLiquid Factory Interface
// interface IGLiquidFactory {
//     function poolByPair(address tokenA, address tokenB) external view returns (address pool);
//     function createPool(address tokenA, address tokenB) external returns (address pool);
//     function defaultConfigurationForPool() external view returns (uint16 communityFee, int24 tickSpacing, uint16 fee);

//     // Role management functions from official docs
//     function POOLS_ADMINISTRATOR_ROLE() external view returns (bytes32);
//     function hasRoleOrOwner(bytes32 role, address account) external view returns (bool);
//     function owner() external view returns (address);
//     function poolDeployer() external view returns (address);
//     function farmingAddress() external view returns (address);
//     function communityVault() external view returns (address);
//     function defaultCommunityFee() external view returns (uint8);
//     function defaultPluginFactory() external view returns (address);

//     event Pool(address indexed token0, address indexed token1, address pool);
// }

// /// @title GLiquid Pool Interface
// interface IGLiquidPool {
//     function token0() external view returns (address);
//     function token1() external view returns (address);
//     function factory() external view returns (address);
//     function globalState()
//         external
//         view
//         returns (uint160 price, int24 tick, uint16 fee, uint16 pluginConfig, uint16 communityFee, bool unlocked);
//     function setCommunityFee(uint16 newCommunityFee) external;
//     function setCommunityVault(address newCommunityVault) external;

//     // Plugin management
//     function plugin() external view returns (address);
//     function pluginConfig() external view returns (uint8);
//     function setPlugin(address newPlugin) external;
//     function setPluginConfig(uint8 newConfig) external;

//     // Fee management for dynamic plugins
//     function setFee(uint16 newFee) external;

//     // Direct liquidity functions
//     function mint(
//         address leftoversRecipient,
//         address recipient,
//         int24 bottomTick,
//         int24 topTick,
//         uint128 liquidityDesired,
//         bytes calldata data
//     ) external returns (uint256 amount0, uint256 amount1, uint128 liquidityActual);

//     function burn(int24 bottomTick, int24 topTick, uint128 amount, bytes calldata data)
//         external
//         returns (uint256 amount0, uint256 amount1);

//     function collect(
//         address recipient,
//         int24 bottomTick,
//         int24 topTick,
//         uint128 amount0Requested,
//         uint128 amount1Requested
//     ) external returns (uint128 amount0, uint128 amount1);

//     struct GlobalState {
//         uint160 price;
//         int24 tick;
//         uint16 fee;
//         uint16 pluginConfig;
//         uint16 communityFee;
//         bool unlocked;
//     }
// }

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

/// @title GLiquid Plugin Interface
/// @notice Interface for GLiquid plugins that extend pool functionality
interface IGLiquidPlugin {
    function beforeInitialize(address sender, address pool) external returns (bytes4);
    function afterInitialize(address sender, address pool, uint160 price, int24 tick) external returns (bytes4);
    function beforeModifyPosition(
        address sender,
        address pool,
        address recipient,
        int24 bottomTick,
        int24 topTick,
        int128 liquidityDelta,
        bytes calldata data
    ) external returns (bytes4);
    function afterModifyPosition(
        address sender,
        address pool,
        address recipient,
        int24 bottomTick,
        int24 topTick,
        int128 liquidityDelta,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external returns (bytes4);
    function beforeSwap(
        address sender,
        address pool,
        address recipient,
        bool zeroToOne,
        int256 amountSpecified,
        uint160 limitSqrtPrice,
        bool withPaymentInAdvance,
        bytes calldata data
    ) external returns (bytes4);
    function afterSwap(
        address sender,
        address pool,
        address recipient,
        bool zeroToOne,
        int256 amountSpecified,
        uint160 limitSqrtPrice,
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) external returns (bytes4);
    function beforeFlash(
        address sender,
        address pool,
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external returns (bytes4);
    function afterFlash(
        address sender,
        address pool,
        address recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 paid0,
        uint256 paid1,
        bytes calldata data
    ) external returns (bytes4);
}

/// @title GLiquid Plugin Factory Interface
/// @notice Interface for creating and managing plugins
interface IGLiquidPluginFactory {
    function createPlugin(address pool, address pluginFactory, bytes32 key) external returns (address plugin);
    function setFarmingAddress(address newFarmingAddress) external;
    function farmingAddress() external view returns (address);
}

/// @title GLiquid Base Plugin Factory Interface
/// @notice Interface for GLiquid's BasePluginV1Factory
interface IGLiquidBasePluginFactory {
    function pluginByPool(address pool) external view returns (address);
    function gliquidFactory() external view returns (address);
    function defaultFeeConfiguration() external view returns (uint16);
}

/// @title GLiquid NonFungiblePositionManager Interface
/// @notice Interface for managing liquidity positions in GLiquid
interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        address deployer;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint88 nonce,
            address operator,
            address token0,
            address token1,
            address deployer,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    // ERC721 functions
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}
