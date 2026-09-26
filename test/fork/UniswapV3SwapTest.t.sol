// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {UniswapV3Swap} from "../../src/UniswapV3Swap.sol";
import {UniswapV3Liquidity} from "../../src/UniswapV3Liquidity.sol";
import {UniswapV3Flash} from "../../src/UniswapV3Flash.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";

/// @title UniswapV3Test - Fork tests against real Uniswap V3 on Ethereum mainnet
/// @notice These tests fork mainnet and interact with the real Uniswap V3 contracts.
///
/// TO RUN THESE TESTS (pick one):
///
///   1. Using a public RPC (free, no API key needed):
///      forge test --fork-url https://ethereum-rpc.publicnode.com -vvv
///.     forge coverage --fork-url https://ethereum-rpc.publicnode.com
///
///   2. Using Alchemy (faster, requires free API key from https://www.alchemy.com):
///      forge test --fork-url https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY -vvv
///
///   3. Using an env variable + foundry.toml [rpc_endpoints]:
///      export MAINNET_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
///      forge test --fork-url mainnet -vvv
///
contract UniswapV3Test is Test {
    // ─── Mainnet Addresses ───────────────────────
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    // ─── Fee Tiers ───────────────────────────────
    uint24 constant FEE_LOW = 500; //   0.05%
    uint24 constant FEE_MEDIUM = 3000; // 0.30%
    uint24 constant FEE_HIGH = 10000; //  1.00%

    // ─── Contracts ───────────────────────────────
    UniswapV3Swap swapContract;
    UniswapV3Liquidity liquidityContract;
    UniswapV3Flash flashContract;

    // ─── Actors ──────────────────────────────────
    address ALICE = makeAddr("alice");

    // ─── Setup ───────────────────────────────────
    function setUp() public {
        // Deploy our interaction contracts
        swapContract = new UniswapV3Swap(SWAP_ROUTER);
        liquidityContract = new UniswapV3Liquidity(POSITION_MANAGER);
        flashContract = new UniswapV3Flash(FACTORY);

        // Fund Alice with WETH using deal()
        // deal() directly sets the balance in the forked state
        deal(WETH, ALICE, 100e18);
        deal(USDC, ALICE, 500_000e6); // USDC has 6 decimals!
        deal(DAI, ALICE, 500_000e18);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 1: SWAPS
    // ═════════════════════════════════════════════════════════════════════

    /// @notice Exact input single-hop: swap 1 WETH → USDC
    function test_swapExactInputSingle() public {
        uint256 amountIn = 1e18; // 1 WETH

        vm.startPrank(ALICE);
        IERC20(WETH).approve(address(swapContract), amountIn);

        uint256 usdcBefore = IERC20(USDC).balanceOf(ALICE);

        uint256 amountOut = swapContract.swapExactInputSingle(WETH, USDC, FEE_MEDIUM, amountIn, 0);

        uint256 usdcAfter = IERC20(USDC).balanceOf(ALICE);
        vm.stopPrank();

        assertGt(amountOut, 0, "Should receive USDC");
        assertEq(usdcAfter - usdcBefore, amountOut, "Balance should increase by amountOut");
        console2.log("Swapped 1 WETH for", amountOut / 1e6, "USDC");
    }

    /// @notice Exact output single-hop: get exactly 1000 USDC, spend minimum WETH
    function test_swapExactOutputSingle() public {
        uint256 amountOut = 1000e6; // 1000 USDC
        uint256 amountInMax = 5e18; // Willing to spend up to 5 WETH

        vm.startPrank(ALICE);
        IERC20(WETH).approve(address(swapContract), amountInMax);

        uint256 wethBefore = IERC20(WETH).balanceOf(ALICE);

        uint256 amountIn = swapContract.swapExactOutputSingle(WETH, USDC, FEE_MEDIUM, amountOut, amountInMax);

        uint256 wethAfter = IERC20(WETH).balanceOf(ALICE);
        vm.stopPrank();

        assertGt(amountIn, 0, "Should spend some WETH");
        assertLe(amountIn, amountInMax, "Should not exceed max input");
        // Alice gets refunded unspent WETH
        assertEq(wethBefore - wethAfter, amountIn, "Should only spend amountIn");
        assertEq(IERC20(USDC).balanceOf(ALICE), 500_000e6 + amountOut, "Should receive exact USDC");
        console2.log("Spent", amountIn, "wei WETH for 1000 USDC");
    }

    /// @notice Multi-hop swap: DAI → USDC → WETH
    function test_swapExactInputMultihop() public {
        uint256 amountIn = 10_000e18; // 10,000 DAI

        // Build the path: DAI → (0.05% pool) → USDC → (0.3% pool) → WETH
        bytes memory path = abi.encodePacked(DAI, FEE_LOW, USDC, FEE_MEDIUM, WETH);

        vm.startPrank(ALICE);
        IERC20(DAI).approve(address(swapContract), amountIn);

        uint256 wethBefore = IERC20(WETH).balanceOf(ALICE);

        uint256 amountOut = swapContract.swapExactInputMultihop(path, amountIn, 0);

        uint256 wethAfter = IERC20(WETH).balanceOf(ALICE);
        vm.stopPrank();

        assertGt(amountOut, 0, "Should receive WETH");
        assertEq(wethAfter - wethBefore, amountOut, "Balance should increase");
        console2.log("Swapped 10,000 DAI for", amountOut, "wei WETH via multi-hop");
    }

    /// @notice Swap reverts with zero amount
    function test_swapRevertsWithZeroAmount() public {
        vm.prank(ALICE);
        vm.expectRevert(UniswapV3Swap.UniswapV3Swap__ZeroAmount.selector);
        swapContract.swapExactInputSingle(WETH, USDC, FEE_MEDIUM, 0, 0);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 2: LIQUIDITY
    // ═════════════════════════════════════════════════════════════════════

    /// @notice Mint a new concentrated liquidity position (USDC/WETH 0.3%)
    function test_mintNewPosition() public {
        // USDC < WETH by address, so USDC is token0, WETH is token1
        // We need to provide liquidity in a price range around the current price

        // Get current tick from the pool
        address pool = IUniswapV3Factory(FACTORY).getPool(USDC, WETH, FEE_MEDIUM);
        (, int24 currentTick,,,,,) = IUniswapV3Pool(pool).slot0();

        // Round tick down to nearest tick spacing (60 for 0.3% fee)
        int24 tickSpacing = 60;
        int24 tickLower = (currentTick / tickSpacing - 10) * tickSpacing;
        int24 tickUpper = (currentTick / tickSpacing + 10) * tickSpacing;

        uint256 amount0 = 10_000e6; // 10,000 USDC
        uint256 amount1 = 5e18; //    5 WETH

        vm.startPrank(ALICE);
        IERC20(USDC).approve(address(liquidityContract), amount0);
        IERC20(WETH).approve(address(liquidityContract), amount1);

        (uint256 tokenId, uint128 liquidity, uint256 used0, uint256 used1) =
            liquidityContract.mintPosition(USDC, WETH, FEE_MEDIUM, tickLower, tickUpper, amount0, amount1);
        vm.stopPrank();

        assertGt(tokenId, 0, "Should receive NFT token ID");
        assertGt(liquidity, 0, "Should have minted liquidity");
        console2.log("Minted position NFT #", tokenId, "with liquidity:", uint256(liquidity));
        console2.log("Used USDC:", used0 / 1e6, "| Used WETH:", used1);
    }

    /// @notice Increase liquidity on an existing position
    function test_increaseLiquidity() public {
        // First mint a position
        (uint256 tokenId, uint128 initialLiquidity) = _mintTestPosition();

        uint256 addAmount0 = 5_000e6;
        uint256 addAmount1 = 2e18;

        vm.startPrank(ALICE);
        IERC20(USDC).approve(address(liquidityContract), addAmount0);
        IERC20(WETH).approve(address(liquidityContract), addAmount1);

        // Need to approve the liquidity contract to manage the NFT
        INonfungiblePositionManager(POSITION_MANAGER).approve(address(liquidityContract), tokenId);

        (uint128 addedLiquidity,,) = liquidityContract.increaseLiquidity(tokenId, USDC, WETH, addAmount0, addAmount1);
        vm.stopPrank();

        assertGt(addedLiquidity, 0, "Should have added liquidity");
        console2.log("Increased liquidity by:", uint256(addedLiquidity));
    }

    /// @notice Decrease liquidity and collect tokens
    function test_decreaseAndCollect() public {
        (uint256 tokenId, uint128 liquidity) = _mintTestPosition();

        uint128 halfLiquidity = liquidity / 2;

        vm.startPrank(ALICE);
        // Need to approve the liquidity contract to manage the NFT
        INonfungiblePositionManager(POSITION_MANAGER).approve(address(liquidityContract), tokenId);

        // Step 1: Decrease liquidity (marks tokens as owed)
        (uint256 amount0Owed, uint256 amount1Owed) = liquidityContract.decreaseLiquidity(tokenId, halfLiquidity);
        vm.stopPrank();

        assertGt(amount0Owed + amount1Owed, 0, "Should have tokens owed");
        console2.log("Decreased liquidity. Owed USDC:", amount0Owed, "| Owed WETH:", amount1Owed);

        // Step 2: Collect the owed tokens
        uint256 usdcBefore = IERC20(USDC).balanceOf(ALICE);
        uint256 wethBefore = IERC20(WETH).balanceOf(ALICE);

        vm.prank(ALICE);
        (uint256 collected0, uint256 collected1) = liquidityContract.collectFees(tokenId);

        assertGe(collected0, amount0Owed, "Should collect at least owed token0");
        assertGe(IERC20(USDC).balanceOf(ALICE), usdcBefore, "USDC balance should increase");
        console2.log("Collected USDC:", collected0, "| Collected WETH:", collected1);
    }

    /// @notice Collect fees after swaps generate them
    function test_collectFeesAfterSwaps() public {
        // 1. Mint a wide liquidity position so swaps pass through it
        (uint256 tokenId,) = _mintTestPosition();

        // 2. Execute some swaps to generate fees
        vm.startPrank(ALICE);
        uint256 swapAmount = 1e18;
        IERC20(WETH).approve(address(swapContract), swapAmount);
        swapContract.swapExactInputSingle(WETH, USDC, FEE_MEDIUM, swapAmount, 0);
        vm.stopPrank();

        // 3. Approve the liquidity contract to manage the NFT, then collect fees
        vm.startPrank(ALICE);
        INonfungiblePositionManager(POSITION_MANAGER).approve(address(liquidityContract), tokenId);
        (uint256 fee0, uint256 fee1) = liquidityContract.collectFees(tokenId);
        vm.stopPrank();

        // Fees may be 0 if the position is too narrow or swap didn't pass through
        // For a wide position, we should see some fees
        console2.log("Fees earned - USDC:", fee0, "| WETH:", fee1);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 3: FLASH LOANS
    // ═════════════════════════════════════════════════════════════════════

    /// @notice Execute a flash loan: borrow USDC and repay with fee
    function test_flashLoanAndRepay() public {
        uint256 borrowAmount = 1_000_000e6; // Borrow 1M USDC

        // Calculate the fee: borrowAmount * poolFee / 1_000_000
        // For 0.3% pool: 1_000_000 * 3000 / 1_000_000 = 3000 USDC
        address pool = IUniswapV3Factory(FACTORY).getPool(USDC, WETH, FEE_MEDIUM);
        uint24 poolFee = IUniswapV3Pool(pool).fee();
        uint256 expectedFee = (borrowAmount * poolFee) / 1_000_000;

        // Fund the flash contract with enough to repay the fee
        // (In a real scenario, the flash loan profit would cover the fee)
        deal(USDC, address(flashContract), borrowAmount + expectedFee);

        // Execute flash loan: borrow USDC (token0 in USDC/WETH pool since USDC < WETH)
        flashContract.flash(USDC, WETH, FEE_MEDIUM, borrowAmount, 0);

        // The flash loan completed successfully (no revert = success)
        console2.log("Flash loan succeeded. Borrowed USDC:", borrowAmount / 1e6, "Fee:", expectedFee / 1e6);
    }

    /// @notice Flash loan with both tokens
    function test_flashLoanBothTokens() public {
        uint256 borrowUsdc = 100_000e6;
        uint256 borrowWeth = 10e18;

        address pool = IUniswapV3Factory(FACTORY).getPool(USDC, WETH, FEE_MEDIUM);
        uint24 poolFee = IUniswapV3Pool(pool).fee();

        uint256 feeUsdc = (borrowUsdc * poolFee) / 1_000_000;
        uint256 feeWeth = (borrowWeth * poolFee) / 1_000_000;

        // Fund the flash contract to cover repayment
        deal(USDC, address(flashContract), borrowUsdc + feeUsdc);
        deal(WETH, address(flashContract), borrowWeth + feeWeth);

        flashContract.flash(USDC, WETH, FEE_MEDIUM, borrowUsdc, borrowWeth);

        console2.log("Dual flash loan succeeded. USDC fee:", feeUsdc, "WETH fee:", feeWeth);
    }

    /// @notice Flash loan reverts with invalid pool
    function test_flashLoanRevertsWithInvalidPool() public {
        vm.expectRevert(UniswapV3Flash.InvalidPool.selector);
        // Use a non-existent pool (WETH/WETH)
        flashContract.flash(WETH, WETH, FEE_MEDIUM, 1e18, 0);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 4: INTEGRATION
    // ═════════════════════════════════════════════════════════════════════

    /// @notice Full lifecycle: mint → swap (fees) → collect → remove
    function test_fullLifecycle() public {
        // 1. Mint position
        (uint256 tokenId, uint128 liquidity) = _mintTestPosition();
        console2.log("1. Minted position #", tokenId);

        // 2. Swap to generate fees
        vm.startPrank(ALICE);
        IERC20(WETH).approve(address(swapContract), 2e18);
        swapContract.swapExactInputSingle(WETH, USDC, FEE_MEDIUM, 2e18, 0);
        console2.log("2. Swapped 2 WETH to generate fees");
        vm.stopPrank();

        // 3. Approve the liquidity contract to manage the NFT
        vm.startPrank(ALICE);
        INonfungiblePositionManager(POSITION_MANAGER).approve(address(liquidityContract), tokenId);

        // 4. Collect fees
        (uint256 fee0, uint256 fee1) = liquidityContract.collectFees(tokenId);
        console2.log("3. Collected fees - USDC:", fee0, "| WETH:", fee1);

        // 5. Remove all liquidity
        liquidityContract.decreaseLiquidity(tokenId, liquidity);
        console2.log("4. Removed all liquidity");

        // 6. Collect the removed liquidity tokens
        (uint256 collected0, uint256 collected1) = liquidityContract.collectFees(tokenId);
        console2.log("5. Collected tokens - USDC:", collected0, "| WETH:", collected1);
        vm.stopPrank();

        assertTrue(collected0 > 0 || collected1 > 0, "Should collect tokens after removing liquidity");
    }

    // ═════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═════════════════════════════════════════════════════════════════════

    /// @dev Mint a test liquidity position and return the tokenId and liquidity
    function _mintTestPosition() internal returns (uint256 tokenId, uint128 liquidity) {
        address pool = IUniswapV3Factory(FACTORY).getPool(USDC, WETH, FEE_MEDIUM);
        (, int24 currentTick,,,,,) = IUniswapV3Pool(pool).slot0();

        // Wide range around current tick
        int24 tickSpacing = 60;
        int24 tickLower = (currentTick / tickSpacing - 10) * tickSpacing;
        int24 tickUpper = (currentTick / tickSpacing + 10) * tickSpacing;

        uint256 amount0 = 50_000e6; // 50k USDC
        uint256 amount1 = 20e18; //   20 WETH

        vm.startPrank(ALICE);
        IERC20(USDC).approve(address(liquidityContract), amount0);
        IERC20(WETH).approve(address(liquidityContract), amount1);

        (tokenId, liquidity,,) =
            liquidityContract.mintPosition(USDC, WETH, FEE_MEDIUM, tickLower, tickUpper, amount0, amount1);
        vm.stopPrank();
    }
}
