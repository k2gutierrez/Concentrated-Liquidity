// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3FlashCallback} from
    "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/// @title UniswapV3Flash — Flash Loan Example
/// @author Blockchain Accelerator - Jose Cruz
/// @notice Demonstrates Uniswap V3 flash loans.
///
/// ══════════════════════════════════════════════════════════════════════════════
/// HOW UNISWAP V3 FLASH LOANS WORK
/// ══════════════════════════════════════════════════════════════════════════════
///
/// A flash loan lets you borrow ANY amount of tokens from a pool, use them,
/// and repay them + a fee — all in ONE transaction. If you don't repay,
/// the entire transaction reverts as if it never happened.
///
/// The flow is:
///   1. Your contract calls pool.flash(recipient, amount0, amount1, data)
///   2. The pool transfers the borrowed tokens to the recipient
///   3. The pool calls uniswapV3FlashCallback(fee0, fee1, data) on msg.sender
///   4. Inside the callback, you DO SOMETHING with the tokens (arbitrage, liquidation, etc.)
///   5. You must transfer back (amount0 + fee0) of token0 and (amount1 + fee1) of token1
///   6. If you don't repay enough, the pool reverts the entire transaction
///
/// FEE CALCULATION:
///   fee = borrowedAmount * poolFee / 1_000_000
///   Example: Borrow 1000 USDC from a 0.3% pool → fee = 1000 * 3000 / 1_000_000 = 3 USDC
///
/// SECURITY:
///   - ALWAYS verify the callback caller is the expected pool!
///   - Otherwise, anyone could call your callback and drain your tokens.
///
contract UniswapV3Flash is IUniswapV3FlashCallback {
    IUniswapV3Factory public immutable FACTORY;

    error UnauthorizedCallback();
    error InvalidPool();

    event FlashLoanExecuted(address indexed pool, uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1);

    constructor(address _factory) {
        FACTORY = IUniswapV3Factory(_factory);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INITIATE FLASH LOAN
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Request a flash loan from a Uniswap V3 pool
    /// @dev The pool will call our uniswapV3FlashCallback after sending tokens.
    /// We must have enough tokens to repay (borrowed + fee) by the end of the callback.
    ///
    /// @param token0 First token of the pool
    /// @param token1 Second token of the pool
    /// @param fee Pool fee tier (to identify the correct pool)
    /// @param amount0 Amount of token0 to borrow (0 if not borrowing)
    /// @param amount1 Amount of token1 to borrow (0 if not borrowing)
    function flash(address token0, address token1, uint24 fee, uint256 amount0, uint256 amount1) external {
        // Find the pool address from the factory
        address pool = FACTORY.getPool(token0, token1, fee);
        if (pool == address(0)) revert InvalidPool();

        // Encode data to pass to the callback (so we know who initiated the flash loan)
        bytes memory data = abi.encode(msg.sender);

        // Request the flash loan — the pool will call our callback next
        IUniswapV3Pool(pool).flash(address(this), amount0, amount1, data);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FLASH LOAN CALLBACK
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Called by the pool after flash-loaned tokens are transferred
    /// @dev This is where you would implement your flash loan logic:
    ///   - Arbitrage between DEXs
    ///   - Liquidate undercollateralized positions
    ///   - Refinance loans
    ///   - Self-liquidation
    ///
    /// In this example, we simply repay the loan + fee (no profit logic).
    /// The caller must have pre-funded this contract with enough tokens.
    ///
    /// SECURITY: We verify that msg.sender is the expected Uniswap V3 pool
    /// by recomputing the pool address from the factory. This prevents
    /// malicious contracts from calling our callback and stealing tokens.
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external override {
        // Decode the original caller
        address caller = abi.decode(data, (address));

        // CRITICAL SECURITY CHECK: Verify the callback is from a legitimate Uniswap V3 pool
        // We get the pool's token0, token1, and fee, then verify via the factory
        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 poolFee = pool.fee();

        address expectedPool = FACTORY.getPool(token0, token1, poolFee);
        if (msg.sender != expectedPool) revert UnauthorizedCallback();

        // ── YOUR FLASH LOAN LOGIC GOES HERE ──
        // At this point, this contract has the borrowed tokens.
        // You could do arbitrage, liquidations, etc.
        // For this example, we just repay.

        // Calculate total repayment amounts
        uint256 repay0 = IERC20(token0).balanceOf(address(this));
        uint256 repay1 = IERC20(token1).balanceOf(address(this));

        // Repay the pool (borrowed amount + fee)
        // The pool checks that it received at least (borrowed + fee) of each token
        if (fee0 > 0 || repay0 > 0) {
            IERC20(token0).transfer(msg.sender, repay0);
        }
        if (fee1 > 0 || repay1 > 0) {
            IERC20(token1).transfer(msg.sender, repay1);
        }

        emit FlashLoanExecuted(msg.sender, repay0 - fee0, repay1 - fee1, fee0, fee1);
    }
}
