// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";

// v2 Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { GlobalAccessList } from "src/protocol-v2/GlobalAccessList.sol";
import { StakingPositions } from "src/protocol-v2/staking/StakingPositions.sol";
import { StakingRewardsDistributor } from "src/protocol-v2/staking/StakingRewardsDistributor.sol";
// v1 Contracts
import { GlobalOwner } from "src/protocol-v1/GlobalOwner.sol";
import { GlobalPause } from "src/protocol-v1/GlobalPause.sol";
import { GlobalBlacklist } from "src/protocol-v1/GlobalBlacklist.sol";
import { GenericERC20 } from "src/protocol-v1/GenericERC20.sol";
import { LDYStaking } from "src/protocol-v1/LDYStaking.sol";
// Contracts
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// Libraries
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Utils } from "tests/protocol-v2/helpers/Utils.sol";
// Mock Contracts
import { MockLToken } from "src/protocol-v1/mock/MockLToken.sol";
import { MockERC20 } from "src/protocol-v1/mock/MockERC20.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAaveLendingPoolV3 } from "src/protocol-v2/interfaces/IAaveLendingPoolV3.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";
import { IStakingPositions } from "src/protocol-v2/interfaces/IStakingPositions.sol";
import { IStakingRewardsDistributor } from "src/protocol-v2/interfaces/IStakingRewardsDistributor.sol";

contract Fixtures is Test {
  // ======== LIBS ======== //
  using Strings for string;

  // ======== CONSTANTS

  uint256 internal constant INITIAL_BALANCE = 1_000_000 ether;
  uint256 internal constant RAY = 1e27;

  // ======== STORAGE ======== //
  uint256 private checkpointSnapshotInitial;
  uint256 private checkpointSnapshot;

  // ======== CONFIGS

  string[] private forkTargets = [
    "MAINNET",
    "BASE",
    "ARBITRUM",
    "HEDERA",
    "SONIC",
    "LINEASCAN"
  ];
  LDYStaking.StakeDurationInfo[] private stakingDurationInfos;
  uint256[] private durations = [0, 1, 6, 12, 24, 36];

  // ======== CONTRACTS

  IERC20 internal usdc;
  IERC20 internal weth;
  MockERC20 internal mockUsdc;
  MockERC20 internal mockWeth;

  GlobalOwner internal globalOwner;
  GlobalPause internal globalPause;
  GlobalBlacklist internal globalBlacklist;
  GlobalAccessList internal globalAccessList;

  GenericERC20 internal ldyToken;
  LDYStaking internal ldyStaking;

  // v2 Staking Contracts
  StakingPositions internal stakingPositions;
  StakingRewardsDistributor internal stakingRewardsDistributor;

  // ======== USERS

  address internal testAccount1 = address(0xA11CE);
  address internal testAccount2 = address(0xB0B);
  address internal testAccount3 = address(0xCA401);
  address internal unauthorizedUser = address(0x666);
  address internal deployer = address(this);

  address[] internal users = [
    testAccount1,
    testAccount2,
    testAccount3
  ];

  address internal feeRecipient = address(0xfee);
  address internal liquidityManager = address(0x777);

  // Actor name mapping
  mapping(address => string) internal actorNames;

  IAaveLendingPoolV3 internal aaveLendingPool;

  // ======== SETUP FUNCTIONS ======== //

  function _selectFork() internal {
    // Fork network based on HARDHAT_DEPLOY_FORK environment variable
    string memory forkTarget = Utils.toUpperCase(
      vm.envOr("HARDHAT_DEPLOY_FORK", string("MAINNET"))
    );

    string memory rpcUrl;
    uint256 forkingBlock;

    for (uint256 i = 0; i < forkTargets.length; i++) {
      if (forkTarget.equal(forkTargets[i])) {
        rpcUrl = vm.envString(
          string.concat(forkTargets[i], "_RPC_URL")
        );
        string memory blockStr = vm.envOr(
          string.concat(forkTargets[i], "_FORKING_BLOCK"),
          string("")
        );
        forkingBlock = bytes(blockStr).length > 0 &&
          !blockStr.equal("latest")
          ? vm.parseUint(blockStr)
          : 0;
        break;
      }
    }

    if (rpcUrl.equal("")) {
      revert(string.concat("Unsupported fork target: ", forkTarget));
    }

    if (forkingBlock > 0) {
      vm.createSelectFork(rpcUrl, forkingBlock);
    } else {
      vm.createSelectFork(rpcUrl);
    }
  }

  function _setUp() internal {
    if (checkpointSnapshotInitial != 0) {
      vm.revertToState(checkpointSnapshotInitial);
    } else {
      _selectFork();

      // Expensive setup
      _deployContracts();
      _setupInitialState();

      // Save snapshot after expensive setup
      checkpointSnapshotInitial = vm.snapshotState();
    }
  }

  function _deployContracts() private {
    for (uint256 i = 0; i < durations.length; i++) {
      stakingDurationInfos.push(
        LDYStaking.StakeDurationInfo(durations[i] * 30 days, 10000)
      );
    }

    // Deploy token
    usdc = _getUsdcToken();
    weth = _getWethToken();
    mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);
    mockWeth = new MockERC20("Mock WETH", "mWETH", 18);
    ldyToken = new GenericERC20("Ledgity Token", "LDY", 18);

    aaveLendingPool = _getAaveV3LendingPool();

    GlobalOwner globalOwnerImpl = new GlobalOwner();
    GlobalPause globalPauseImpl = new GlobalPause();
    GlobalBlacklist globalBlacklistImpl = new GlobalBlacklist();
    GlobalAccessList globalAccessListImpl = new GlobalAccessList();
    LDYStaking ldyStakingImpl = new LDYStaking();
    StakingPositions stakingPositionsImpl = new StakingPositions();
    StakingRewardsDistributor stakingRewardsDistributorImpl = new StakingRewardsDistributor();

    // Deploy proxies
    ERC1967Proxy globalOwnerProxy = new ERC1967Proxy(
      address(globalOwnerImpl),
      ""
    );
    ERC1967Proxy globalPauseProxy = new ERC1967Proxy(
      address(globalPauseImpl),
      ""
    );
    ERC1967Proxy globalBlacklistProxy = new ERC1967Proxy(
      address(globalBlacklistImpl),
      ""
    );
    ERC1967Proxy globalAccessListProxy = new ERC1967Proxy(
      address(globalAccessListImpl),
      ""
    );
    ERC1967Proxy ldyStakingProxy = new ERC1967Proxy(
      address(ldyStakingImpl),
      ""
    );
    ERC1967Proxy stakingPositionsProxy = new ERC1967Proxy(
      address(stakingPositionsImpl),
      ""
    );
    ERC1967Proxy stakingRewardsDistributorProxy = new ERC1967Proxy(
      address(stakingRewardsDistributorImpl),
      ""
    );

    globalOwner = GlobalOwner(address(globalOwnerProxy));
    globalPause = GlobalPause(address(globalPauseProxy));
    globalBlacklist = GlobalBlacklist(address(globalBlacklistProxy));
    globalAccessList = GlobalAccessList(
      address(globalAccessListProxy)
    );
    ldyStaking = LDYStaking(address(ldyStakingProxy));
    stakingPositions = StakingPositions(address(stakingPositionsProxy));
    stakingRewardsDistributor = StakingRewardsDistributor(
      address(stakingRewardsDistributorProxy)
    );

    // Setup labels
    vm.label(address(usdc), "USDC token");
    vm.label(address(weth), "WETH token");
    vm.label(address(mockUsdc), "Mock USDC token");
    vm.label(address(mockWeth), "Mock WETH token");
    vm.label(address(ldyToken), "LDY token");
    vm.label(address(aaveLendingPool), "Aave Lending Pool");
    //
    vm.label(address(globalOwner), "GlobalOwner");
    vm.label(address(globalPause), "GlobalPause");
    vm.label(address(globalBlacklist), "GlobalBlacklist");
    vm.label(address(globalAccessList), "GlobalAccessList");
    vm.label(address(ldyStaking), "LDYStaking");
    vm.label(address(stakingPositions), "StakingPositions");
    vm.label(address(stakingRewardsDistributor), "StakingRewardsDistributor");
    //
    vm.label(testAccount1, "Alice");
    vm.label(testAccount2, "Bob");
    vm.label(testAccount3, "Carol");
    vm.label(unauthorizedUser, "Unauthorized User");
    vm.label(deployer, "Deployer");
    vm.label(feeRecipient, "Fee Recipient");
    vm.label(liquidityManager, "Liquidity Manager");

    // Setup actor name mapping
    actorNames[testAccount1] = "Alice";
    actorNames[testAccount2] = "Bob";
    actorNames[testAccount3] = "Carol";
    actorNames[liquidityManager] = "Liquidity Manager";
    actorNames[feeRecipient] = "Fee Recipient";
    actorNames[address(this)] = "Owner";
  }

  function _setupInitialState() private {
    globalOwner.initialize();
    globalPause.initialize(address(globalOwner));
    globalBlacklist.initialize(address(globalOwner));
    globalAccessList.initialize(address(globalOwner));

    ldyStaking.initialize(
      address(globalOwner),
      address(globalPause),
      address(globalBlacklist),
      address(ldyToken),
      stakingDurationInfos,
      12 * 30 days,
      1000 * 1e18
    );

    // Initialize v2 staking contracts
    stakingPositions.initialize(
      address(ldyToken),
      address(globalOwner),
      address(globalPause),
      address(globalAccessList)
    );

    stakingRewardsDistributor.initialize(
      address(stakingPositions),
      address(globalOwner),
      address(globalPause),
      address(globalAccessList)
    );

    for (uint256 i; i < users.length; i++) {
      deal(users[i], INITIAL_BALANCE);

      deal(address(usdc), users[i], INITIAL_BALANCE);
      deal(address(weth), users[i], INITIAL_BALANCE);
      mockUsdc.mint(users[i], INITIAL_BALANCE);
      mockWeth.mint(users[i], INITIAL_BALANCE);
    }
  }

  // ======== ACTION FUNCTIONS ======== //

  function _createLToken(
    IERC20 asset_
  ) internal returns (MockLToken) {
    MockLToken lTokenImpl = new MockLToken();
    ERC1967Proxy lTokenProxy = new ERC1967Proxy(
      address(lTokenImpl),
      ""
    );
    MockLToken lToken = MockLToken(address(lTokenProxy));

    string memory name = string.concat(
      "Ledgity ",
      MockERC20(address(asset_)).symbol()
    );
    string memory symbol = string.concat(
      "L",
      MockERC20(address(asset_)).symbol()
    );

    lToken.initialize(
      address(globalOwner),
      address(globalPause),
      address(globalBlacklist),
      address(ldyStaking),
      address(asset_),
      name,
      symbol
    );

    return lToken;
  }

  function _createVault(
    IERC20 asset_,
    IERC20 lToken_
  ) internal returns (LedgityYieldVault) {
    return _createVaultWithConfig(asset_, lToken_, true);
  }

  function _createVaultWithConfig(
    IERC20 asset_,
    IERC20 lToken_,
    bool hasAave_
  ) internal returns (LedgityYieldVault) {
    LedgityYieldVault yieldVaultImpl = new LedgityYieldVault();
    ERC1967Proxy yieldVaultProxy = new ERC1967Proxy(
      address(yieldVaultImpl),
      ""
    );
    LedgityYieldVault yieldVault = LedgityYieldVault(
      address(yieldVaultProxy)
    );

    string memory name = string.concat(
      "Ledgity ",
      MockERC20(address(asset_)).name(),
      hasAave_ ? " (Aave)" : ""
    );
    string memory symbol = string.concat(
      "ly",
      MockERC20(address(asset_)).symbol()
    );

    ILedgityYieldVault.VaultParams memory vaultParams = ILedgityYieldVault
      .VaultParams({
        name: name,
        symbol: symbol,
        asset: asset_,
        lToken: lToken_,
        stakeToken: ldyToken,
        stakeForFeeReduction: 1000 * 1e18,
        stakeForInstantWithdrawal: 0,
        globalOwner: address(globalOwner),
        globalPause: address(globalPause),
        globalAccessList: address(globalAccessList),
        liquidityManager: liquidityManager,
        feeRecipient: payable(feeRecipient),
        liquidityBufferRate: (10 * RAY) / 100, // 10% in RAY
        aaveLendingPool: hasAave_
          ? aaveLendingPool
          : IAaveLendingPoolV3(address(0))
      });

    IVaultLiquidityModule.VaultLiquidityInitParams
      memory vaultLiquidityInitParams = IVaultLiquidityModule
        .VaultLiquidityInitParams({
          highWaterMark: 0, // defaults to 1:1 ratio
          deploymentDelay: 1,
          initialAssetsPerShare: 0, // defaults to 1:1
          yieldAPR: (5 * RAY) / 100, // 5% APR in RAY
          managementFeeRate: (2 * RAY) / 1000, // 0.2% in RAY
          performanceFeeRate: (2 * RAY) / 100, // 2% in RAY
          withdrawalFeeRate: (5 * RAY) / 10000, // 0.05% in RAY
          withdrawalGasFee: 0.001 ether
        });

    yieldVault.initialize(vaultParams, vaultLiquidityInitParams);

    return yieldVault;
  }

  function _setupApprovalsForVault(
    LedgityYieldVault vault,
    IERC20 asset
  ) internal {
    address[] memory accounts = new address[](4);
    accounts[0] = testAccount1;
    accounts[1] = testAccount2;
    accounts[2] = testAccount3;
    accounts[3] = liquidityManager;

    for (uint256 i = 0; i < accounts.length; i++) {
      vm.prank(accounts[i]);
      asset.approve(address(vault), type(uint256).max);
    }
  }

  // ======== HELPER FUNCTIONS ======== //

  function _getAaveV3LendingPool()
    internal
    view
    returns (IAaveLendingPoolV3)
  {
    if (block.chainid == 1) {
      // Mainnet
      return
        IAaveLendingPoolV3(
          0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
        );
    } else if (block.chainid == 42161) {
      // Arbitrum
      return
        IAaveLendingPoolV3(
          0x794a61358D6845594F94dc1DB02A252b5b4814aD
        );
    } else if (block.chainid == 59144) {
      // Linea
      return
        IAaveLendingPoolV3(
          0xc47b8C00b0f69a36fa203Ffeac0334874574a8Ac
        );
    } else if (block.chainid == 8453) {
      // Base
      return
        IAaveLendingPoolV3(
          0xA238Dd80C259a72e81d7e4664a9801593F98d1c5
        );
    } else if (block.chainid == 146) {
      // Sonic
      return
        IAaveLendingPoolV3(
          0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3
        );
    }
    revert("AaveLendingPool not set");
  }

  function _getUsdcToken() internal view returns (IERC20) {
    if (block.chainid == 1) {
      // Mainnet
      return IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    } else if (block.chainid == 42161) {
      // Arbitrum
      return IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    }
    revert("USDC not set");
  }

  function _getWethToken() internal view returns (IERC20) {
    if (block.chainid == 1) {
      // Mainnet
      return IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    } else if (block.chainid == 42161) {
      // Arbitrum
      return IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }
    revert("WETH not set");
  }
}
