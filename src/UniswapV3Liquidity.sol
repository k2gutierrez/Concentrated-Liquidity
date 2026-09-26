// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";

/// @title UniswapV3Liquidity — Concentrated Liquidity Management
/// @author Blockchain Accelerator - Jose Cruz
/// @notice Demonstrates how to provide liquidity on Uniswap V3.
///
/// ══════════════════════════════════════════════════════════════════════════════
/// CONCENTRATED LIQUIDITY — The Big Innovation in V3
/// ══════════════════════════════════════════════════════════════════════════════
///
/// In Uniswap V2, liquidity was spread across the ENTIRE price range (0 to ∞).
/// This was capital-inefficient — most of the liquidity was never used.
///
/// In Uniswap V3, LPs choose a SPECIFIC price range for their liquidity:
///   - tickLower = lower bound of the price range
///   - tickUpper = upper bound of the price range
///
/// Your liquidity is only active (earns fees) when the current price is within
/// your range. Tighter ranges = more fees per dollar, but higher risk of going
/// out of range.
///
/// TICKS:
///   - Ticks represent discrete price points: price = 1.0001^tick
///   - Tick 0 = price 1.0
///   - Tick 23027 ≈ price 10.0
///   - tickLower and tickUpper must be multiples of the pool's tick spacing
///   - Fee 500 (0.05%) → tickSpacing = 10
///   - Fee 3000 (0.3%) → tickSpacing = 60
///   - Fee 10000 (1%) → tickSpacing = 200
///
/// POSITIONS AS NFTs:
///   - Each liquidity position is minted as an ERC-721 NFT
///   - The NFT represents: which pool + which tick range + how much liquidity
///   - You can transfer, sell, or use the NFT as collateral
///
contract UniswapV3Liquidity {
    error ZeroAmount();

    INonfungiblePositionManager public immutable POSITION_MANAGER;

    event PositionMinted(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event LiquidityIncreased(uint256 indexed tokenId, uint128 liquidity);
    event LiquidityDecreased(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event FeesCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    constructor(address _positionManager) {
        POSITION_MANAGER = INonfungiblePositionManager(_positionManager);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MINT — Create a new liquidity position
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Mint a new concentrated liquidity position
    /// @dev Creates an NFT representing the position. The caller must approve
    /// this contract to spend both tokens before calling.
    ///
    /// IMPORTANT: token0 must be < token1 (sorted by address).
    /// If you pass them in wrong order, the transaction will fail.
    ///
    /// @param token0 The first token (lower address)
    /// @param token1 The second token (higher address)
    /// @param fee The pool fee tier
    /// @param tickLower Lower bound of the price range (must be multiple of tick spacing)
    /// @param tickUpper Upper bound of the price range (must be multiple of tick spacing)
    /// @param amount0Desired Desired amount of token0
    /// @param amount1Desired Desired amount of token1
    /// @return tokenId The NFT token ID of the position
    /// @return liquidity The amount of liquidity minted
    /// @return amount0 Actual amount of token0 deposited
    /// @return amount1 Actual amount of token1 deposited
    function mintPosition(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        // Transfer tokens from caller
        IERC20(token0).transferFrom(msg.sender, address(this), amount0Desired);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1Desired);

        // Approve the position manager
        IERC20(token0).approve(address(POSITION_MANAGER), amount0Desired);
        IERC20(token1).approve(address(POSITION_MANAGER), amount1Desired);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0, // No slippage protection in this example
            amount1Min: 0,
            recipient: msg.sender, // Caller receives the NFT
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = POSITION_MANAGER.mint(params);

        // Refund unused tokens
        if (amount0 < amount0Desired) {
            IERC20(token0).approve(address(POSITION_MANAGER), 0);
            IERC20(token0).transfer(msg.sender, amount0Desired - amount0);
        }
        if (amount1 < amount1Desired) {
            IERC20(token1).approve(address(POSITION_MANAGER), 0);
            IERC20(token1).transfer(msg.sender, amount1Desired - amount1);
        }

        emit PositionMinted(tokenId, liquidity, amount0, amount1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INCREASE LIQUIDITY — Add more to an existing position
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Add more liquidity to an existing position
    /// @dev The caller must own the NFT (or be approved). The tick range stays the same.
    /// @param tokenId The NFT token ID of the position
    /// @param token0 The first token of the pool (must match the position)
    /// @param token1 The second token of the pool (must match the position)
    /// @param amount0Desired Desired amount of token0 to add
    /// @param amount1Desired Desired amount of token1 to add
    function increaseLiquidity(
        uint256 tokenId,
        address token0,
        address token1,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        IERC20(token0).transferFrom(msg.sender, address(this), amount0Desired);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1Desired);
        IERC20(token0).approve(address(POSITION_MANAGER), amount0Desired);
        IERC20(token1).approve(address(POSITION_MANAGER), amount1Desired);

        (liquidity, amount0, amount1) = POSITION_MANAGER.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        // Refund unused tokens
        if (amount0 < amount0Desired) {
            IERC20(token0).transfer(msg.sender, amount0Desired - amount0);
        }
        if (amount1 < amount1Desired) {
            IERC20(token1).transfer(msg.sender, amount1Desired - amount1);
        }

        emit LiquidityIncreased(tokenId, liquidity);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DECREASE LIQUIDITY — Remove from an existing position
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Remove liquidity from a position
    /// @dev This does NOT transfer tokens — it only marks them as "owed".
    /// You must call collectFees() afterward to actually receive the tokens.
    /// This is a two-step process by design in Uniswap V3.
    function decreaseLiquidity(uint256 tokenId, uint128 liquidity)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = POSITION_MANAGER.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        emit LiquidityDecreased(tokenId, amount0, amount1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COLLECT — Withdraw tokens (fees + removed liquidity)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Collect all tokens owed to a position
    /// @dev This collects BOTH:
    ///   1. Trading fees earned by the position
    ///   2. Tokens from decreased liquidity (if decreaseLiquidity was called first)
    ///
    /// Use type(uint128).max to collect everything owed.
    function collectFees(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = POSITION_MANAGER.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: msg.sender,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        emit FeesCollected(tokenId, amount0, amount1);
    }

}