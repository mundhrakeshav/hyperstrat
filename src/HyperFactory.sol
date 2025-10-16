// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import "./HyperStrategy.sol";
import "./HyperInterfaces.sol";
import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";

/// @title Hyyper Factory - https://hyperstr.xyz
contract HyperFactory is Ownable {
    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               STATE VARIABLES                               */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    ISwapRouter public immutable swapRouter;

    bool public routerRestrict;
    mapping(address => bool) public validRouter; // Approved routers for trading
    mapping(address => address) public collectionToStrategy; // Collection => Strategy
    mapping(address => address) public strategyToCollection; // Strategy => Collection

    uint256 public deploymentFee = 0.001 ether; // Fee to deploy a new strategy
    uint256 public constant MAX_DEPLOYMENT_FEE = 1 ether;

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                CUSTOM EVENTS                                */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    event StrategyDeployed(
        address indexed strategy, address indexed collection, string name, string symbol, address deployer
    );
    event RouterStatusUpdated(address indexed router, bool status);
    event RouterRestrictUpdated(bool status);
    event DeploymentFeeUpdated(uint256 newFee);
    event FeesWithdrawn(address indexed to, uint256 amount);
    event InitialTokensTransferred(address indexed strategy, address indexed recipient, uint256 amount);

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                CUSTOM ERRORS                                */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    error InvalidAddress();
    error InvalidSwapRouter();
    error InvalidGLiquidFactory();
    error InvalidOwner();
    error InvalidCollection();
    error InvalidFeeCollector();
    error StrategyAlreadyExists();
    error InsufficientDeploymentFee();
    error DeploymentFeeTooHigh();
    error TransferFailed();
    error NoFeesToWithdraw();

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                                 CONSTRUCTOR                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Initializes the factory
    /// @param _swapRouter Address of GLiquid SwapRouter
    /// @param _owner Address of the factory owner
    constructor(ISwapRouter _swapRouter, address _owner) {
        if (address(_swapRouter) == address(0)) {
            revert InvalidSwapRouter();
        }

        if (_owner == address(0)) {
            revert InvalidOwner();
        }

        swapRouter = _swapRouter;

        _initializeOwner(_owner);

        // Approve GLiquid SwapRouter by default
        validRouter[address(_swapRouter)] = true;
        emit RouterStatusUpdated(address(_swapRouter), true);
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                            DEPLOYMENT FUNCTIONS                             */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Deploys a new HyperStrategy for an NFT collection
    /// @param _collection Address of the NFT collection
    /// @param _tokenName Name of the strategy token
    /// @param _tokenSymbol Symbol of the strategy token
    /// @param _feeCollector Address that will collect and deposit trading fees
    /// @return strategy Address of the deployed strategy contract
    function deployStrategy(
        address _collection,
        string memory _tokenName,
        string memory _tokenSymbol,
        address _feeCollector
    ) external payable returns (address strategy) {
        // Check deployment fee
        if (msg.value < deploymentFee) revert InsufficientDeploymentFee();

        // Validate inputs
        if (_collection == address(0)) {
            revert InvalidCollection();
        }
        if (_feeCollector == address(0)) {
            revert InvalidFeeCollector();
        }

        // Check if strategy already exists for this collection
        if (collectionToStrategy[_collection] != address(0)) {
            revert StrategyAlreadyExists();
        }

        // Deploy new strategy
        HyperStrategy newStrategy =
            new HyperStrategy(_tokenName, _tokenSymbol, address(this), swapRouter, _collection, _feeCollector);

        strategy = address(newStrategy);

        // Register strategy
        collectionToStrategy[_collection] = strategy;
        strategyToCollection[strategy] = _collection;

        emit StrategyDeployed(strategy, _collection, _tokenName, _tokenSymbol, msg.sender);

        // Refund excess payment
        if (msg.value > deploymentFee) {
            SafeTransferLib.forceSafeTransferETH(msg.sender, msg.value - deploymentFee);
        }

        return strategy;
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                              ADMIN FUNCTIONS                                */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Sets router approval status
    /// @param _router Address of the router
    /// @param _status Approval status
    function setRouter(address _router, bool _status) external onlyOwner {
        if (_router == address(0)) revert InvalidAddress();
        validRouter[_router] = _status;
        emit RouterStatusUpdated(_router, _status);
    }

    /// @notice Enables or disables router restrictions globally
    /// @param _status True to enable restrictions, false to disable
    function setRouterRestrict(bool _status) external onlyOwner {
        routerRestrict = _status;
        emit RouterRestrictUpdated(_status);
    }

    /// @notice Updates the deployment fee
    /// @param _newFee New deployment fee in wei
    function setDeploymentFee(uint256 _newFee) external onlyOwner {
        if (_newFee > MAX_DEPLOYMENT_FEE) revert DeploymentFeeTooHigh();
        deploymentFee = _newFee;
        emit DeploymentFeeUpdated(_newFee);
    }

    /// @notice Withdraws accumulated deployment fees
    /// @param _to Address to receive the fees
    function withdrawFees(address _to) external onlyOwner {
        if (_to == address(0)) revert InvalidAddress();
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoFeesToWithdraw();

        SafeTransferLib.forceSafeTransferETH(_to, balance);
        emit FeesWithdrawn(_to, balance);
    }

    /// @notice Updates strategy parameters
    /// @param _strategy Address of the strategy
    /// @param _newMultiplier New price multiplier
    function updateStrategyMultiplier(address _strategy, uint256 _newMultiplier) external onlyOwner {
        IHyperStrategy(_strategy).setPriceMultiplier(_newMultiplier);
    }

    /// @notice Updates strategy name
    /// @param _strategy Address of the strategy
    /// @param _newName New name
    function updateStrategyName(address _strategy, string memory _newName) external onlyOwner {
        IHyperStrategy(_strategy).updateName(_newName);
    }

    /// @notice Updates strategy symbol
    /// @param _strategy Address of the strategy
    /// @param _newSymbol New symbol
    function updateStrategySymbol(address _strategy, string memory _newSymbol) external onlyOwner {
        IHyperStrategy(_strategy).updateSymbol(_newSymbol);
    }

    /// @notice Updates strategy fee collector
    /// @param _strategy Address of the strategy
    /// @param _newFeeCollector New fee collector address
    function updateStrategyFeeCollector(address _strategy, address _newFeeCollector) external onlyOwner {
        if (_strategy == address(0) || _newFeeCollector == address(0)) revert InvalidAddress();
        if (strategyToCollection[_strategy] == address(0)) revert("Strategy not found");

        IHyperStrategy(_strategy).setFeeCollector(_newFeeCollector);
    }

    /// @notice Whitelists or removes a marketplace for a strategy
    /// @param _strategy Address of the strategy
    /// @param _marketplace Address of the marketplace contract
    /// @param _status True to whitelist, false to remove
    function setStrategyMarketplaceWhitelist(address _strategy, address _marketplace, bool _status)
        external
        onlyOwner
    {
        if (_strategy == address(0) || _marketplace == address(0)) revert InvalidAddress();
        if (strategyToCollection[_strategy] == address(0)) revert("Strategy not found");

        IHyperStrategy(_strategy).setMarketplaceWhitelist(_marketplace, _status);
    }

    /// @notice Transfers initial tokens from factory to recipient for liquidity provision
    /// @param _strategy Address of the strategy token contract
    /// @param _recipient Address to receive the tokens
    /// @param _amount Amount of tokens to transfer
    /// @dev Only owner can call this. Useful for providing initial liquidity
    function transferInitialTokens(address _strategy, address _recipient, uint256 _amount) external onlyOwner {
        if (_strategy == address(0) || _recipient == address(0)) revert InvalidAddress();
        if (strategyToCollection[_strategy] == address(0)) revert("Strategy not found");

        IERC20(_strategy).transfer(_recipient, _amount);

        emit InitialTokensTransferred(_strategy, _recipient, _amount);
    }

    /// @notice Get token balance of factory for a specific strategy
    /// @param _strategy Address of the strategy token contract
    /// @return balance Token balance of factory
    function getFactoryTokenBalance(address _strategy) external view returns (uint256 balance) {
        return IERC20(_strategy).balanceOf(address(this));
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                              VIEW FUNCTIONS                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Checks if a transfer is valid based on router restrictions
    /// @param from Sender address
    /// @param to Receiver address
    /// @param tokenAddress Strategy token address
    /// @return bool True if transfer is allowed
    function validTransfer(address from, address to, address tokenAddress) external view returns (bool) {
        // If restrictions are disabled, allow all transfers
        if (!routerRestrict) return true;

        // Allow minting (from address(0))
        if (from == address(0)) return true;

        // Allow burning (to address(0) or DEAD_ADDRESS)
        if (to == address(0) || to == HyperStrategy(payable(tokenAddress)).DEAD_ADDRESS()) {
            return true;
        }

        // Allow transfers from/to the strategy contract itself
        if (from == tokenAddress || to == tokenAddress) return true;

        // Allow transfers from/to approved routers
        if (validRouter[from] || validRouter[to]) return true;

        // Allow transfers from/to the factory
        if (from == address(this) || to == address(this)) return true;

        // Deny all other transfers
        return false;
    }

    /// @notice Allows contract to receive ETH
    receive() external payable {}
}
