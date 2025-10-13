// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAlgebraFactory {
    /// @notice role that can change communityFee and tickspacing in pools
    /// @return The hash corresponding to this role
    function POOLS_ADMINISTRATOR_ROLE() external view returns (bytes32);

    /// @notice role that can call `createCustomPool` function
    /// @return The hash corresponding to this role
    function CUSTOM_POOL_DEPLOYER() external view returns (bytes32);

    /// @notice Returns `true` if `account` has been granted `role` or `account` is owner.
    /// @param role The hash corresponding to the role
    /// @param account The address for which the role is checked
    /// @return bool Whether the address has this role or the owner role or not
    function hasRoleOrOwner(bytes32 role, address account) external view returns (bool);

    /// @notice Returns the current owner of the factory
    /// @dev Can be changed by the current owner via transferOwnership(address newOwner)
    /// @return The address of the factory owner
    function owner() external view returns (address);

    /// @notice Returns the current poolDeployerAddress
    /// @return The address of the poolDeployer
    function poolDeployer() external view returns (address);

    /// @notice Returns the default community fee
    /// @return Fee which will be set at the creation of the pool
    function defaultCommunityFee() external view returns (uint16);

    /// @notice Returns the default fee
    /// @return Fee which will be set at the creation of the pool
    function defaultFee() external view returns (uint16);

    /// @notice Return the current pluginFactory address
    /// @dev This contract is used to automatically set a plugin address in new liquidity pools
    /// @return Algebra plugin factory
    function defaultPluginFactory() external view returns (address);

    /// @notice Returns the default communityFee, tickspacing, fee and communityFeeVault for pool
    /// @return communityFee which will be set at the creation of the pool
    /// @return tickSpacing which will be set at the creation of the pool
    /// @return fee which will be set at the creation of the pool
    function defaultConfigurationForPool() external view returns (uint16 communityFee, int24 tickSpacing, uint16 fee);

    /// @notice Deterministically computes the pool address given the token0 and token1
    /// @dev The method does not check if such a pool has been created
    /// @param token0 first token
    /// @param token1 second token
    /// @return pool The contract address of the Algebra pool
    function computePoolAddress(address token0, address token1) external view returns (address pool);

    /// @notice Deterministically computes the custom pool address given the customDeployer, token0 and token1
    /// @dev The method does not check if such a pool has been created
    /// @param customDeployer the address of custom plugin deployer
    /// @param token0 first token
    /// @param token1 second token
    /// @return customPool The contract address of the Algebra pool
    function computeCustomPoolAddress(address customDeployer, address token0, address token1)
        external
        view
        returns (address customPool);

    /// @notice Returns the pool address for a given pair of tokens, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @return pool The pool address
    function poolByPair(address tokenA, address tokenB) external view returns (address pool);

    /// @notice Returns the custom pool address for a customDeployer and a given pair of tokens, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param customDeployer The address of custom plugin deployer
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @return customPool The pool address
    function customPoolByPair(address customDeployer, address tokenA, address tokenB)
        external
        view
        returns (address customPool);

    /// @notice Creates a pool for the given two tokens
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    /// @param data Data for plugin creation
    /// @dev tokenA and tokenB may be passed in either order: token0/token1 or token1/token0.
    /// The call will revert if the pool already exists or the token arguments are invalid.
    /// @return pool The address of the newly created pool
    function createPool(address tokenA, address tokenB, bytes calldata data) external returns (address pool);

    /// @notice Creates a custom pool for the given two tokens using `deployer` contract
    /// @param deployer The address of plugin deployer, also used for custom pool address calculation
    /// @param creator The initiator of custom pool creation
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    /// @param data The additional data bytes
    /// @dev tokenA and tokenB may be passed in either order: token0/token1 or token1/token0.
    /// The call will revert if the pool already exists or the token arguments are invalid.
    /// @return customPool The address of the newly created custom pool
    function createCustomPool(address deployer, address creator, address tokenA, address tokenB, bytes calldata data)
        external
        returns (address customPool);

    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function grantRole(bytes32 role, address account) external;
}
