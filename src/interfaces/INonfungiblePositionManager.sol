// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

/// @title INonfungiblePositionManager — Minimal interface for Uniswap V3 position management
/// @author Blockchain Accelerator - Jose Cruz
/// @notice Extracted from @uniswap/v3-periphery INonfungiblePositionManager.
///
/// WHY A LOCAL COPY?
/// The real INonfungiblePositionManager inherits from OpenZeppelin v3.x ERC721
/// interfaces (IERC721Metadata, IERC721Enumerable) which use `pragma ^0.7.0`.
/// This creates an irreconcilable version conflict with Solidity 0.8.x projects.
///
/// This minimal interface mirrors the exact structs and function signatures from
/// the real contract, allowing our 0.8.26 code to interact with the deployed
/// NonfungiblePositionManager without pulling in the incompatible dependency tree.
///
/// All other Uniswap V3 interfaces (ISwapRouter, IUniswapV3Pool, IUniswapV3Factory,
/// IUniswapV3FlashCallback) are imported directly from the real libraries since
/// they use `pragma >=0.5.0` or `pragma >=0.7.5` without problematic dependencies.
interface INonfungiblePositionManager {
    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS — Identical to the real INonfungiblePositionManager
    // ═══════════════════════════════════════════════════════════════════════

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
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

    // ═══════════════════════════════════════════════════════════════════════
    // POSITION MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Creates a new position wrapped in an NFT
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Increases liquidity in an existing position
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Decreases liquidity in an existing position
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    /// @notice Collects tokens owed to a position
    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    /// @notice Returns the position information associated with a given token ID
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    // ═══════════════════════════════════════════════════════════════════════
    // ERC-721 (from the inherited IERC721 in the real contract)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Approve an address to manage a specific NFT position
    function approve(address to, uint256 tokenId) external;
}
