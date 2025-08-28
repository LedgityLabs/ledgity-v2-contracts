**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [arbitrary-send-erc20](#arbitrary-send-erc20) (3 results) (High)
 - [weak-prng](#weak-prng) (2 results) (High)
 - [incorrect-exp](#incorrect-exp) (2 results) (High)
 - [reentrancy-eth](#reentrancy-eth) (2 results) (High)
 - [unchecked-transfer](#unchecked-transfer) (16 results) (High)
 - [divide-before-multiply](#divide-before-multiply) (24 results) (Medium)
 - [incorrect-equality](#incorrect-equality) (16 results) (Medium)
 - [reentrancy-no-eth](#reentrancy-no-eth) (9 results) (Medium)
 - [uninitialized-local](#uninitialized-local) (17 results) (Medium)
 - [write-after-write](#write-after-write) (1 results) (Medium)
## arbitrary-send-erc20
Impact: High
Confidence: High
 - [ ] ID-0
[ERC4626Upgradeable._deposit(address,address,uint256,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol#L218-L230) uses arbitrary from in transferFrom: [SafeERC20Upgradeable.safeTransferFrom(_asset,caller,address(this),assets)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol#L226)

node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol#L218-L230


 - [ ] ID-1
[LedgityYieldVault.processRequests(uint256[],uint256)](src/protocol-v2/LedgityYieldVault.sol#L729-L788) uses arbitrary from in transferFrom: [IERC20(asset()).safeTransferFrom(liquidityManager,address(this),addedLiquidity)](src/protocol-v2/LedgityYieldVault.sol#L734-L738)

src/protocol-v2/LedgityYieldVault.sol#L729-L788


 - [ ] ID-2
[LedgityYieldVault.depositToBuffer(uint256)](src/protocol-v2/LedgityYieldVault.sol#L702-L712) uses arbitrary from in transferFrom: [IERC20(asset()).safeTransferFrom(liquidityManager,address(this),amount)](src/protocol-v2/LedgityYieldVault.sol#L706-L710)

src/protocol-v2/LedgityYieldVault.sol#L702-L712


## weak-prng
Impact: High
Confidence: Medium
 - [ ] ID-3
[WrappedLTokenHedera.exchangeRate()](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L129-L164) uses a weak PRNG: "[remainingTime = timeElapsed % 86400](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L141)" 

src/protocol-v1/hedera/WrappedLTokenHedera.sol#L129-L164


 - [ ] ID-4
[WrappedLToken.exchangeRate()](src/protocol-v1/WrappedLToken.sol#L114-L149) uses a weak PRNG: "[remainingTime = timeElapsed % 86400](src/protocol-v1/WrappedLToken.sol#L126)" 

src/protocol-v1/WrappedLToken.sol#L114-L149


## incorrect-exp
Impact: High
Confidence: Medium
 - [ ] ID-5
[MathUpgradeable.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134) has bitwise-xor operator ^ instead of the exponentiation operator **: 
	 - [inverse = (3 * denominator) ^ 2](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L116)

node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134


 - [ ] ID-6
[Math.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134) has bitwise-xor operator ^ instead of the exponentiation operator **: 
	 - [inverse = (3 * denominator) ^ 2](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L116)

node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134


## reentrancy-eth
Impact: High
Confidence: Medium
 - [ ] ID-7
Reentrancy in [LToken.deposit(uint256,string)](src/protocol-v1/LToken.sol#L673-L701):
	External calls:
	- [super.depositFor(_msgSender(),amount)](src/protocol-v1/LToken.sol#L697)
		- [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol#L122)
		- [SafeERC20Upgradeable.safeTransferFrom(_underlying,sender,address(this),amount)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20WrapperUpgradeable.sol#L57)
		- [(success,returndata) = target.call{value: value}(data)](node_modules/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol#L135)
		- [transfersListeners[i].onLTokenTransfer(from,to,amount)](src/protocol-v1/LToken.sol#L599)
	- [_transferExceedingToFund()](src/protocol-v1/LToken.sol#L700)
		- [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol#L122)
		- [(success,returndata) = target.call{value: value}(data)](node_modules/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol#L135)
		- [underlying().safeTransfer(fund,exceedingAmount)](src/protocol-v1/LToken.sol#L641)
	External calls sending eth:
	- [super.depositFor(_msgSender(),amount)](src/protocol-v1/LToken.sol#L697)
		- [(success,returndata) = target.call{value: value}(data)](node_modules/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol#L135)
	- [_transferExceedingToFund()](src/protocol-v1/LToken.sol#L700)
		- [(success,returndata) = target.call{value: value}(data)](node_modules/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol#L135)
	State variables written after the call(s):
	- [_transferExceedingToFund()](src/protocol-v1/LToken.sol#L700)
		- [usableUnderlyings -= exceedingAmount](src/protocol-v1/LToken.sol#L638)
	[LToken.usableUnderlyings](src/protocol-v1/LToken.sol#L153) can be used in cross function reentrancies:
	- [LToken._transferExceedingToFund()](src/protocol-v1/LToken.sol#L627-L642)
	- [LToken.claimFees()](src/protocol-v1/LToken.sol#L1152-L1169)
	- [LToken.deposit(uint256,string)](src/protocol-v1/LToken.sol#L673-L701)
	- [LToken.instantWithdrawal(uint256)](src/protocol-v1/LToken.sol#L738-L792)
	- [LToken.processBigQueuedRequest(uint256)](src/protocol-v1/LToken.sol#L1002-L1082)
	- [LToken.processQueuedRequests()](src/protocol-v1/LToken.sol#L867-L992)
	- [LToken.recoverUnderlying()](src/protocol-v1/LToken.sol#L511-L523)
	- [LToken.repatriate(uint256)](src/protocol-v1/LToken.sol#L1127-L1149)
	- [LToken.usableUnderlyings](src/protocol-v1/LToken.sol#L153)

src/protocol-v1/LToken.sol#L673-L701


 - [ ] ID-8
Reentrancy in [LDYStaking.unstake(uint256,uint256)](src/protocol-v1/LDYStaking.sol#L247-L304):
	External calls:
	- [_claimReward(_msgSender(),stakeIndex)](src/protocol-v1/LDYStaking.sol#L294)
		- [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol#L122)
		- [(success,returndata) = target.call{value: value}(data)](node_modules/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol#L135)
		- [stakeRewardToken.safeTransfer(account,reward)](src/protocol-v1/LDYStaking.sol#L538)
	External calls sending eth:
	- [_claimReward(_msgSender(),stakeIndex)](src/protocol-v1/LDYStaking.sol#L294)
		- [(success,returndata) = target.call{value: value}(data)](node_modules/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol#L135)
	State variables written after the call(s):
	- [userStakingInfo[_msgSender()][stakeIndex] = userStakingInfo[_msgSender()][userStakingInfo[_msgSender()].length - 1]](src/protocol-v1/LDYStaking.sol#L296-L298)
	[LDYStaking.userStakingInfo](src/protocol-v1/LDYStaking.sol#L89) can be used in cross function reentrancies:
	- [LDYStaking._updateReward(address,uint256)](src/protocol-v1/LDYStaking.sol#L549-L564)
	- [LDYStaking.earned(address,uint256)](src/protocol-v1/LDYStaking.sol#L459-L472)
	- [LDYStaking.getEarnedUser(address)](src/protocol-v1/LDYStaking.sol#L479-L488)
	- [LDYStaking.getUserStakes(address)](src/protocol-v1/LDYStaking.sol#L508-L512)
	- [LDYStaking.userStakingInfo](src/protocol-v1/LDYStaking.sol#L89)
	- [userStakingInfo[_msgSender()].pop()](src/protocol-v1/LDYStaking.sol#L299)
	[LDYStaking.userStakingInfo](src/protocol-v1/LDYStaking.sol#L89) can be used in cross function reentrancies:
	- [LDYStaking._updateReward(address,uint256)](src/protocol-v1/LDYStaking.sol#L549-L564)
	- [LDYStaking.earned(address,uint256)](src/protocol-v1/LDYStaking.sol#L459-L472)
	- [LDYStaking.getEarnedUser(address)](src/protocol-v1/LDYStaking.sol#L479-L488)
	- [LDYStaking.getUserStakes(address)](src/protocol-v1/LDYStaking.sol#L508-L512)
	- [LDYStaking.userStakingInfo](src/protocol-v1/LDYStaking.sol#L89)

src/protocol-v1/LDYStaking.sol#L247-L304


## unchecked-transfer
Impact: High
Confidence: Medium
 - [ ] ID-9
[WrappedLTokenHedera.depositAndWrap(uint256)](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L294-L315) ignores return value by [underlying.transferFrom(msg.sender,address(this),underlyingAmount)](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L303-L307)

src/protocol-v1/hedera/WrappedLTokenHedera.sol#L294-L315


 - [ ] ID-10
[LTokenHedera.deposit(uint256,string)](src/protocol-v1/hedera/LTokenHedera.sol#L638-L667) ignores return value by [underlying().transferFrom(_msgSender(),address(this),amount)](src/protocol-v1/hedera/LTokenHedera.sol#L662)

src/protocol-v1/hedera/LTokenHedera.sol#L638-L667


 - [ ] ID-11
[LTokenHedera.repatriate(uint256)](src/protocol-v1/hedera/LTokenHedera.sol#L1094-L1112) ignores return value by [underlying().transferFrom(_msgSender(),address(this),amount)](src/protocol-v1/hedera/LTokenHedera.sol#L1111)

src/protocol-v1/hedera/LTokenHedera.sol#L1094-L1112


 - [ ] ID-12
[LTokenHedera.processQueuedRequests()](src/protocol-v1/hedera/LTokenHedera.sol#L834-L959) ignores return value by [underlying().transfer(request.account,withdrawnAmount)](src/protocol-v1/hedera/LTokenHedera.sol#L937)

src/protocol-v1/hedera/LTokenHedera.sol#L834-L959


 - [ ] ID-13
[LTokenHedera.processBigQueuedRequest(uint256)](src/protocol-v1/hedera/LTokenHedera.sol#L969-L1049) ignores return value by [underlying().transfer(request.account,missingAmount)](src/protocol-v1/hedera/LTokenHedera.sol#L1044)

src/protocol-v1/hedera/LTokenHedera.sol#L969-L1049


 - [ ] ID-14
[WrappedLTokenHedera.depositAndWrap(uint256,address)](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L322-L344) ignores return value by [underlying.transferFrom(msg.sender,address(this),underlyingAmount)](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L332-L336)

src/protocol-v1/hedera/WrappedLTokenHedera.sol#L322-L344


 - [ ] ID-15
[WrappedLTokenHedera._wrap(uint256,address,address)](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L229-L253) ignores return value by [lToken.transferFrom(from,address(this),lTokenAmount)](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L247)

src/protocol-v1/hedera/WrappedLTokenHedera.sol#L229-L253


 - [ ] ID-16
[WrappedLToken._unwrap(uint256,address,address)](src/protocol-v1/WrappedLToken.sol#L247-L271) ignores return value by [lToken.transfer(to,lTokenAmount_)](src/protocol-v1/WrappedLToken.sol#L268)

src/protocol-v1/WrappedLToken.sol#L247-L271


 - [ ] ID-17
[WrappedLTokenHedera._unwrap(uint256,address,address)](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L262-L286) ignores return value by [lToken.transfer(to,lTokenAmount_)](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L283)

src/protocol-v1/hedera/WrappedLTokenHedera.sol#L262-L286


 - [ ] ID-18
[LTokenHedera.processBigQueuedRequest(uint256)](src/protocol-v1/hedera/LTokenHedera.sol#L969-L1049) ignores return value by [underlying().transferFrom(_msgSender(),request.account,withdrawnAmount)](src/protocol-v1/hedera/LTokenHedera.sol#L1022-L1026)

src/protocol-v1/hedera/LTokenHedera.sol#L969-L1049


 - [ ] ID-19
[AdministeredUpgradable.recoverERC20(address,uint256)](src/protocol-v2/modules/AdministeredUpgradable.sol#L128-L137) ignores return value by [IERC20(tokenAddress).transfer(msg.sender,amount)](src/protocol-v2/modules/AdministeredUpgradable.sol#L135)

src/protocol-v2/modules/AdministeredUpgradable.sol#L128-L137


 - [ ] ID-20
[LTokenHedera.claimFees()](src/protocol-v1/hedera/LTokenHedera.sol#L1115-L1132) ignores return value by [underlying().transfer(owner(),fees)](src/protocol-v1/hedera/LTokenHedera.sol#L1131)

src/protocol-v1/hedera/LTokenHedera.sol#L1115-L1132


 - [ ] ID-21
[WrappedLToken._wrap(uint256,address,address)](src/protocol-v1/WrappedLToken.sol#L214-L238) ignores return value by [lToken.transferFrom(from,address(this),lTokenAmount)](src/protocol-v1/WrappedLToken.sol#L232)

src/protocol-v1/WrappedLToken.sol#L214-L238


 - [ ] ID-22
[LTokenHedera._transferExceedingToFund()](src/protocol-v1/hedera/LTokenHedera.sol#L592-L607) ignores return value by [underlying().transfer(fund,exceedingAmount)](src/protocol-v1/hedera/LTokenHedera.sol#L606)

src/protocol-v1/hedera/LTokenHedera.sol#L592-L607


 - [ ] ID-23
[LTokenHedera.processBigQueuedRequest(uint256)](src/protocol-v1/hedera/LTokenHedera.sol#L969-L1049) ignores return value by [underlying().transferFrom(_msgSender(),request.account,fundBalance)](src/protocol-v1/hedera/LTokenHedera.sol#L1037-L1041)

src/protocol-v1/hedera/LTokenHedera.sol#L969-L1049


 - [ ] ID-24
[LTokenHedera.instantWithdrawal(uint256)](src/protocol-v1/hedera/LTokenHedera.sol#L704-L759) ignores return value by [underlying().transfer(_msgSender(),withdrawnAmount)](src/protocol-v1/hedera/LTokenHedera.sol#L758)

src/protocol-v1/hedera/LTokenHedera.sol#L704-L759


## divide-before-multiply
Impact: Medium
Confidence: Medium
 - [ ] ID-25
[MathUpgradeable.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L101)
	- [inverse *= 2 - denominator * inverse](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L121)

node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134


 - [ ] ID-26
[WrappedLToken.exchangeRate()](src/protocol-v1/WrappedLToken.sol#L114-L149) performs a multiplication on the result of a division:
	- [compoundedRate = (compoundedRate * (RAY + dailyRatio)) / RAY](src/protocol-v1/WrappedLToken.sol#L135)
	- [compoundedRate = (compoundedRate * (RAY + remainingRatio)) / RAY](src/protocol-v1/WrappedLToken.sol#L143-L145)

src/protocol-v1/WrappedLToken.sol#L114-L149


 - [ ] ID-27
[Math.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L101)
	- [inverse *= 2 - denominator * inverse](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L120)

node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134


 - [ ] ID-28
[MathUpgradeable.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L101)
	- [inverse *= 2 - denominator * inverse](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L124)

node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134


 - [ ] ID-29
[Math.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134) performs a multiplication on the result of a division:
	- [prod0 = prod0 / twos](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L104)
	- [result = prod0 * inverse](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L131)

node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134


 - [ ] ID-30
[Math.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L101)
	- [inverse *= 2 - denominator * inverse](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L122)

node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134


 - [ ] ID-31
[VaultLiquidityModule._registerFundRevenue()](src/protocol-v2/modules/VaultLiquidityModule.sol#L367-L379) performs a multiplication on the result of a division:
	- [fullDays = timeElapsed / 86400](src/protocol-v2/modules/VaultLiquidityModule.sol#L375)
	- [lastCompoundTime += fullDays * 86400](src/protocol-v2/modules/VaultLiquidityModule.sol#L376)

src/protocol-v2/modules/VaultLiquidityModule.sol#L367-L379


 - [ ] ID-32
[MathUpgradeable.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L101)
	- [inverse *= 2 - denominator * inverse](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L120)

node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134


 - [ ] ID-33
[Math.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L101)
	- [inverse *= 2 - denominator * inverse](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L125)

node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134


 - [ ] ID-34
[WrappedLToken.exchangeRate()](src/protocol-v1/WrappedLToken.sol#L114-L149) performs a multiplication on the result of a division:
	- [aprBaseOneRay = lastCheckpoint.apr / 100](src/protocol-v1/WrappedLToken.sol#L129)
	- [remainingRatio = (aprBaseOneRay * remainingTime) / (31536000)](src/protocol-v1/WrappedLToken.sol#L141-L142)

src/protocol-v1/WrappedLToken.sol#L114-L149


 - [ ] ID-35
[MathUpgradeable.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L101)
	- [inverse *= 2 - denominator * inverse](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L125)

node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134


 - [ ] ID-36
[WrappedLTokenHedera.exchangeRate()](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L129-L164) performs a multiplication on the result of a division:
	- [compoundedRate = (compoundedRate * (RAY + dailyRatio)) / RAY](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L150)
	- [compoundedRate = (compoundedRate * (RAY + remainingRatio)) / RAY](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L158-L160)

src/protocol-v1/hedera/WrappedLTokenHedera.sol#L129-L164


 - [ ] ID-37
[Math.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L101)
	- [inverse *= 2 - denominator * inverse](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L124)

node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134


 - [ ] ID-38
[Math.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L101)
	- [inverse *= 2 - denominator * inverse](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L123)

node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134


 - [ ] ID-39
[InvestUpgradeable._calculatePeriodRewards(uint40,uint40,uint16,uint256)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L265-L292) performs a multiplication on the result of a division:
	- [growthSUD = (elapsedYearsSUD * aprSUD) / SUD.fromInt(1,d)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L284-L285)
	- [rewardsSUD = (investedAmountSUD * growthSUD) / SUD.fromInt(100,d)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L289-L290)

src/protocol-v1/abstracts/InvestUpgradeable.sol#L265-L292


 - [ ] ID-40
[Math.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L101)
	- [inverse *= 2 - denominator * inverse](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L121)

node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134


 - [ ] ID-41
[InvestUpgradeable._calculatePeriodRewards(uint40,uint40,uint16,uint256)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L265-L292) performs a multiplication on the result of a division:
	- [elapsedYearsSUD = (elapsedTimeSUD * SUD.fromInt(1,d)) / SUD.fromInt(31536000,d)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L279-L280)
	- [growthSUD = (elapsedYearsSUD * aprSUD) / SUD.fromInt(1,d)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L284-L285)

src/protocol-v1/abstracts/InvestUpgradeable.sol#L265-L292


 - [ ] ID-42
[MathUpgradeable.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L101)
	- [inverse = (3 * denominator) ^ 2](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L116)

node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134


 - [ ] ID-43
[MathUpgradeable.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L101)
	- [inverse *= 2 - denominator * inverse](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L122)

node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134


 - [ ] ID-44
[Math.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L101)
	- [inverse = (3 * denominator) ^ 2](node_modules/@openzeppelin/contracts/utils/math/Math.sol#L116)

node_modules/@openzeppelin/contracts/utils/math/Math.sol#L55-L134


 - [ ] ID-45
[LDYStaking.earned(address,uint256)](src/protocol-v1/LDYStaking.sol#L459-L472) performs a multiplication on the result of a division:
	- [weightedAmount = (userInfo.stakedAmount * multiplier) / MULTIPLIER_BASIS](src/protocol-v1/LDYStaking.sol#L467-L468)
	- [rewardsSinceLastUpdate = ((weightedAmount * (rewardPerToken() - userInfo.rewardPerTokenPaid)) / 1e18)](src/protocol-v1/LDYStaking.sol#L469-L470)

src/protocol-v1/LDYStaking.sol#L459-L472


 - [ ] ID-46
[MathUpgradeable.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134) performs a multiplication on the result of a division:
	- [prod0 = prod0 / twos](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L104)
	- [result = prod0 * inverse](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L131)

node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134


 - [ ] ID-47
[WrappedLTokenHedera.exchangeRate()](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L129-L164) performs a multiplication on the result of a division:
	- [aprBaseOneRay = lastCheckpoint.apr / 100](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L144)
	- [remainingRatio = (aprBaseOneRay * remainingTime) / (31536000)](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L156-L157)

src/protocol-v1/hedera/WrappedLTokenHedera.sol#L129-L164


 - [ ] ID-48
[MathUpgradeable.mulDiv(uint256,uint256,uint256)](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134) performs a multiplication on the result of a division:
	- [denominator = denominator / twos](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L101)
	- [inverse *= 2 - denominator * inverse](node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L123)

node_modules/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol#L55-L134


## incorrect-equality
Impact: Medium
Confidence: High
 - [ ] ID-49
[VaultLiquidityModule._registerFundRevenue()](src/protocol-v2/modules/VaultLiquidityModule.sol#L367-L379) uses a dangerous strict equality:
	- [timeElapsed == 0](src/protocol-v2/modules/VaultLiquidityModule.sol#L369)

src/protocol-v2/modules/VaultLiquidityModule.sol#L367-L379


 - [ ] ID-50
[WrappedLToken._unwrap(uint256,address,address)](src/protocol-v1/WrappedLToken.sol#L247-L271) uses a dangerous strict equality:
	- [wrappedAmount == 0](src/protocol-v1/WrappedLToken.sol#L252)

src/protocol-v1/WrappedLToken.sol#L247-L271


 - [ ] ID-51
[WrappedLTokenHedera._unwrap(uint256,address,address)](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L262-L286) uses a dangerous strict equality:
	- [wrappedAmount == 0](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L267)

src/protocol-v1/hedera/WrappedLTokenHedera.sol#L262-L286


 - [ ] ID-52
[LedgityYieldVault.getBufferRewardRate()](src/protocol-v2/LedgityYieldVault.sol#L258-L271) uses a dangerous strict equality:
	- [totalVaultAssets == 0 || ! hasBufferStrategy](src/protocol-v2/LedgityYieldVault.sol#L262)

src/protocol-v2/LedgityYieldVault.sol#L258-L271


 - [ ] ID-53
[WrappedLToken._wrap(uint256,address,address)](src/protocol-v1/WrappedLToken.sol#L214-L238) uses a dangerous strict equality:
	- [lTokenAmount == 0](src/protocol-v1/WrappedLToken.sol#L219)

src/protocol-v1/WrappedLToken.sol#L214-L238


 - [ ] ID-54
[InvestUpgradeable._beforeInvestmentChange(address,bool)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L445-L488) uses a dangerous strict equality:
	- [accountsDetails[account].period.timestamp == uint40(block.timestamp)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L457-L458)

src/protocol-v1/abstracts/InvestUpgradeable.sol#L445-L488


 - [ ] ID-55
[InvestUpgradeable._rewardsOf(address,bool)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L326-L412) uses a dangerous strict equality:
	- [details.period.timestamp == 0 || investedAmount == 0](src/protocol-v1/abstracts/InvestUpgradeable.sol#L337)

src/protocol-v1/abstracts/InvestUpgradeable.sol#L326-L412


 - [ ] ID-56
[LedgityYieldVault._deposit(address,address,uint256,uint256)](src/protocol-v2/LedgityYieldVault.sol#L407-L469) uses a dangerous strict equality:
	- [assets_ == 0](src/protocol-v2/LedgityYieldVault.sol#L418)

src/protocol-v2/LedgityYieldVault.sol#L407-L469


 - [ ] ID-57
[VaultLiquidityModule._takeFees(address)](src/protocol-v2/modules/VaultLiquidityModule.sol#L386-L404) uses a dangerous strict equality:
	- [timeElapsed == 0](src/protocol-v2/modules/VaultLiquidityModule.sol#L388)

src/protocol-v2/modules/VaultLiquidityModule.sol#L386-L404


 - [ ] ID-58
[LToken.recoverUnderlying()](src/protocol-v1/LToken.sol#L511-L523) uses a dangerous strict equality:
	- [recoverableAmount == 0](src/protocol-v1/LToken.sol#L519)

src/protocol-v1/LToken.sol#L511-L523


 - [ ] ID-59
[WrappedLTokenHedera._wrap(uint256,address,address)](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L229-L253) uses a dangerous strict equality:
	- [lTokenAmount == 0](src/protocol-v1/hedera/WrappedLTokenHedera.sol#L234)

src/protocol-v1/hedera/WrappedLTokenHedera.sol#L229-L253


 - [ ] ID-60
[VaultLiquidityModule._computeFeeData()](src/protocol-v2/modules/VaultLiquidityModule.sol#L266-L334) uses a dangerous strict equality:
	- [sharesDenominator == 0](src/protocol-v2/modules/VaultLiquidityModule.sol#L293)

src/protocol-v2/modules/VaultLiquidityModule.sol#L266-L334


 - [ ] ID-61
[VaultLiquidityModule.convertToShares(uint256)](src/protocol-v2/modules/VaultLiquidityModule.sol#L178-L189) uses a dangerous strict equality:
	- [supply == 0 || currentAssets == 0](src/protocol-v2/modules/VaultLiquidityModule.sol#L184)

src/protocol-v2/modules/VaultLiquidityModule.sol#L178-L189


 - [ ] ID-62
[LedgityYieldVault._withdraw(address,address,address,uint256,uint256)](src/protocol-v2/LedgityYieldVault.sol#L478-L522) uses a dangerous strict equality:
	- [shares_ == 0](src/protocol-v2/LedgityYieldVault.sol#L490)

src/protocol-v2/LedgityYieldVault.sol#L478-L522


 - [ ] ID-63
[VaultLiquidityModule.convertToAssets(uint256)](src/protocol-v2/modules/VaultLiquidityModule.sol#L196-L207) uses a dangerous strict equality:
	- [supply == 0 || currentAssets == 0](src/protocol-v2/modules/VaultLiquidityModule.sol#L202)

src/protocol-v2/modules/VaultLiquidityModule.sol#L196-L207


 - [ ] ID-64
[LTokenHedera.recoverUnderlying()](src/protocol-v1/hedera/LTokenHedera.sol#L478-L493) uses a dangerous strict equality:
	- [recoverableAmount == 0](src/protocol-v1/hedera/LTokenHedera.sol#L486)

src/protocol-v1/hedera/LTokenHedera.sol#L478-L493


## reentrancy-no-eth
Impact: Medium
Confidence: Medium
 - [ ] ID-65
Reentrancy in [LTokenHedera.processBigQueuedRequest(uint256)](src/protocol-v1/hedera/LTokenHedera.sol#L969-L1049):
	External calls:
	- [underlying().transferFrom(_msgSender(),request.account,withdrawnAmount)](src/protocol-v1/hedera/LTokenHedera.sol#L1022-L1026)
	- [underlying().transferFrom(_msgSender(),request.account,fundBalance)](src/protocol-v1/hedera/LTokenHedera.sol#L1037-L1041)
	- [underlying().transfer(request.account,missingAmount)](src/protocol-v1/hedera/LTokenHedera.sol#L1044)
	- [_transferExceedingToFund()](src/protocol-v1/hedera/LTokenHedera.sol#L1048)
		- [underlying().transfer(fund,exceedingAmount)](src/protocol-v1/hedera/LTokenHedera.sol#L606)
	State variables written after the call(s):
	- [_transferExceedingToFund()](src/protocol-v1/hedera/LTokenHedera.sol#L1048)
		- [usableUnderlyings -= exceedingAmount](src/protocol-v1/hedera/LTokenHedera.sol#L603)
	[LTokenHedera.usableUnderlyings](src/protocol-v1/hedera/LTokenHedera.sol#L152) can be used in cross function reentrancies:
	- [LTokenHedera._transferExceedingToFund()](src/protocol-v1/hedera/LTokenHedera.sol#L592-L607)
	- [LTokenHedera.claimFees()](src/protocol-v1/hedera/LTokenHedera.sol#L1115-L1132)
	- [LTokenHedera.deposit(uint256,string)](src/protocol-v1/hedera/LTokenHedera.sol#L638-L667)
	- [LTokenHedera.instantWithdrawal(uint256)](src/protocol-v1/hedera/LTokenHedera.sol#L704-L759)
	- [LTokenHedera.processBigQueuedRequest(uint256)](src/protocol-v1/hedera/LTokenHedera.sol#L969-L1049)
	- [LTokenHedera.processQueuedRequests()](src/protocol-v1/hedera/LTokenHedera.sol#L834-L959)
	- [LTokenHedera.recoverUnderlying()](src/protocol-v1/hedera/LTokenHedera.sol#L478-L493)
	- [LTokenHedera.repatriate(uint256)](src/protocol-v1/hedera/LTokenHedera.sol#L1094-L1112)
	- [LTokenHedera.usableUnderlyings](src/protocol-v1/hedera/LTokenHedera.sol#L152)

src/protocol-v1/hedera/LTokenHedera.sol#L969-L1049


 - [ ] ID-66
Reentrancy in [LedgityYieldVault._withdraw(address,address,address,uint256,uint256)](src/protocol-v2/LedgityYieldVault.sol#L478-L522):
	External calls:
	- [IERC20(address(this)).safeTransferFrom(caller_,feeRecipient,withdrawalFee)](src/protocol-v2/LedgityYieldVault.sol#L502-L506)
	State variables written after the call(s):
	- [_burn(caller_,netShares)](src/protocol-v2/LedgityYieldVault.sol#L512)
		- [_balances[account] = accountBalance - amount](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L290)
	[ERC20Upgradeable._balances](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L40) can be used in cross function reentrancies:
	- [ERC20Upgradeable._burn(address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L282-L298)
	- [ERC20Upgradeable._mint(address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L256-L269)
	- [ERC20Upgradeable._transfer(address,address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L227-L245)
	- [ERC20Upgradeable.balanceOf(address)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L106-L108)
	- [_withdrawAssets(netAssets)](src/protocol-v2/LedgityYieldVault.sol#L513)
		- [_totalAssets = totalAssets()](src/protocol-v2/modules/VaultLiquidityModule.sol#L372)
		- [_totalAssets -= assets](src/protocol-v2/modules/VaultLiquidityModule.sol#L364)
	[VaultLiquidityModule._totalAssets](src/protocol-v2/modules/VaultLiquidityModule.sol#L47) can be used in cross function reentrancies:
	- [VaultLiquidityModule._addAssets(uint256)](src/protocol-v2/modules/VaultLiquidityModule.sol#L343-L349)
	- [VaultLiquidityModule._registerFundRevenue()](src/protocol-v2/modules/VaultLiquidityModule.sol#L367-L379)
	- [VaultLiquidityModule._withdrawAssets(uint256)](src/protocol-v2/modules/VaultLiquidityModule.sol#L356-L365)
	- [VaultLiquidityModule.setTotalAssets(uint256)](src/protocol-v2/modules/VaultLiquidityModule.sol#L413-L421)
	- [VaultLiquidityModule.totalAssets()](src/protocol-v2/modules/VaultLiquidityModule.sol#L142-L171)
	- [_burn(caller_,netShares)](src/protocol-v2/LedgityYieldVault.sol#L512)
		- [_totalSupply -= amount](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L292)
	[ERC20Upgradeable._totalSupply](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L44) can be used in cross function reentrancies:
	- [ERC20Upgradeable._burn(address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L282-L298)
	- [ERC20Upgradeable._mint(address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L256-L269)
	- [ERC20Upgradeable.totalSupply()](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L99-L101)
	- [_withdrawAssets(netAssets)](src/protocol-v2/LedgityYieldVault.sol#L513)
		- [lastCompoundTime += fullDays * 86400](src/protocol-v2/modules/VaultLiquidityModule.sol#L376)
	[VaultLiquidityModule.lastCompoundTime](src/protocol-v2/modules/VaultLiquidityModule.sol#L52) can be used in cross function reentrancies:
	- [VaultLiquidityModule.__VaultLiquidityModule_init(VaultLiquidityModule.VaultLiquidityInitParams,address)](src/protocol-v2/modules/VaultLiquidityModule.sol#L83-L106)
	- [VaultLiquidityModule._registerFundRevenue()](src/protocol-v2/modules/VaultLiquidityModule.sol#L367-L379)
	- [VaultLiquidityModule.lastCompoundTime](src/protocol-v2/modules/VaultLiquidityModule.sol#L52)
	- [VaultLiquidityModule.setTotalAssets(uint256)](src/protocol-v2/modules/VaultLiquidityModule.sol#L413-L421)
	- [VaultLiquidityModule.totalAssets()](src/protocol-v2/modules/VaultLiquidityModule.sol#L142-L171)

src/protocol-v2/LedgityYieldVault.sol#L478-L522


 - [ ] ID-67
Reentrancy in [LedgityYieldVault.migrateLToken(uint256)](src/protocol-v2/LedgityYieldVault.sol#L532-L556):
	External calls:
	- [lToken.safeTransferFrom(msg.sender,liquidityManager,amount)](src/protocol-v2/LedgityYieldVault.sol#L546)
	State variables written after the call(s):
	- [_mint(msg.sender,shares)](src/protocol-v2/LedgityYieldVault.sol#L552)
		- [_balances[account] += amount](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L264)
	[ERC20Upgradeable._balances](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L40) can be used in cross function reentrancies:
	- [ERC20Upgradeable._burn(address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L282-L298)
	- [ERC20Upgradeable._mint(address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L256-L269)
	- [ERC20Upgradeable._transfer(address,address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L227-L245)
	- [ERC20Upgradeable.balanceOf(address)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L106-L108)
	- [_addAssets(amount)](src/protocol-v2/LedgityYieldVault.sol#L553)
		- [_totalAssets += assets](src/protocol-v2/modules/VaultLiquidityModule.sol#L348)
		- [_totalAssets = totalAssets()](src/protocol-v2/modules/VaultLiquidityModule.sol#L372)
	[VaultLiquidityModule._totalAssets](src/protocol-v2/modules/VaultLiquidityModule.sol#L47) can be used in cross function reentrancies:
	- [VaultLiquidityModule._addAssets(uint256)](src/protocol-v2/modules/VaultLiquidityModule.sol#L343-L349)
	- [VaultLiquidityModule._registerFundRevenue()](src/protocol-v2/modules/VaultLiquidityModule.sol#L367-L379)
	- [VaultLiquidityModule._withdrawAssets(uint256)](src/protocol-v2/modules/VaultLiquidityModule.sol#L356-L365)
	- [VaultLiquidityModule.setTotalAssets(uint256)](src/protocol-v2/modules/VaultLiquidityModule.sol#L413-L421)
	- [VaultLiquidityModule.totalAssets()](src/protocol-v2/modules/VaultLiquidityModule.sol#L142-L171)
	- [_mint(msg.sender,shares)](src/protocol-v2/LedgityYieldVault.sol#L552)
		- [_totalSupply += amount](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L261)
	[ERC20Upgradeable._totalSupply](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L44) can be used in cross function reentrancies:
	- [ERC20Upgradeable._burn(address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L282-L298)
	- [ERC20Upgradeable._mint(address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L256-L269)
	- [ERC20Upgradeable.totalSupply()](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L99-L101)
	- [_addAssets(amount)](src/protocol-v2/LedgityYieldVault.sol#L553)
		- [lastCompoundTime += fullDays * 86400](src/protocol-v2/modules/VaultLiquidityModule.sol#L376)
	[VaultLiquidityModule.lastCompoundTime](src/protocol-v2/modules/VaultLiquidityModule.sol#L52) can be used in cross function reentrancies:
	- [VaultLiquidityModule.__VaultLiquidityModule_init(VaultLiquidityModule.VaultLiquidityInitParams,address)](src/protocol-v2/modules/VaultLiquidityModule.sol#L83-L106)
	- [VaultLiquidityModule._registerFundRevenue()](src/protocol-v2/modules/VaultLiquidityModule.sol#L367-L379)
	- [VaultLiquidityModule.lastCompoundTime](src/protocol-v2/modules/VaultLiquidityModule.sol#L52)
	- [VaultLiquidityModule.setTotalAssets(uint256)](src/protocol-v2/modules/VaultLiquidityModule.sol#L413-L421)
	- [VaultLiquidityModule.totalAssets()](src/protocol-v2/modules/VaultLiquidityModule.sol#L142-L171)

src/protocol-v2/LedgityYieldVault.sol#L532-L556


 - [ ] ID-68
Reentrancy in [PreMining.processUnlockRequests()](src/protocol-v1/PreMining.sol#L402-L437):
	External calls:
	- [underlyingToken.safeTransfer(unlockAccount,unlockAmount)](src/protocol-v1/PreMining.sol#L428)
	State variables written after the call(s):
	- [delete unlockRequests[processedId]](src/protocol-v1/PreMining.sol#L425)
	[PreMining.unlockRequests](src/protocol-v1/PreMining.sol#L108) can be used in cross function reentrancies:
	- [PreMining.processUnlockRequests()](src/protocol-v1/PreMining.sol#L402-L437)
	- [PreMining.requestUnlock()](src/protocol-v1/PreMining.sol#L389-L396)
	- [PreMining.unlockRequests](src/protocol-v1/PreMining.sol#L108)
	- [unlockRequestsCursor = processedId](src/protocol-v1/PreMining.sol#L436)
	[PreMining.unlockRequestsCursor](src/protocol-v1/PreMining.sol#L111) can be used in cross function reentrancies:
	- [PreMining.processUnlockRequests()](src/protocol-v1/PreMining.sol#L402-L437)
	- [PreMining.unlockRequestsCursor](src/protocol-v1/PreMining.sol#L111)

src/protocol-v1/PreMining.sol#L402-L437


 - [ ] ID-69
Reentrancy in [LedgityYieldVault._deposit(address,address,uint256,uint256)](src/protocol-v2/LedgityYieldVault.sol#L407-L469):
	External calls:
	- [IERC20(asset()).safeTransferFrom(caller_,address(this),assets_)](src/protocol-v2/LedgityYieldVault.sol#L457)
	- [_depositBuffer(bufferAmount)](src/protocol-v2/LedgityYieldVault.sol#L461)
		- [aaveLendingPool.deposit(asset(),amountAssets,address(this),0)](src/protocol-v2/LedgityYieldVault.sol#L381)
	State variables written after the call(s):
	- [_depositBuffer(bufferAmount)](src/protocol-v2/LedgityYieldVault.sol#L461)
		- [lastBufferRewardBalance += amountAssets](src/protocol-v2/LedgityYieldVault.sol#L383)
	[LedgityYieldVault.lastBufferRewardBalance](src/protocol-v2/LedgityYieldVault.sol#L100) can be used in cross function reentrancies:
	- [LedgityYieldVault._bufferRewards()](src/protocol-v2/LedgityYieldVault.sol#L366-L372)
	- [LedgityYieldVault._depositBuffer(uint256)](src/protocol-v2/LedgityYieldVault.sol#L378-L384)
	- [LedgityYieldVault._withdrawBuffer(address,uint256)](src/protocol-v2/LedgityYieldVault.sol#L393-L397)
	- [LedgityYieldVault.harvestFees()](src/protocol-v2/LedgityYieldVault.sol#L684-L693)
	- [LedgityYieldVault.lastBufferRewardBalance](src/protocol-v2/LedgityYieldVault.sol#L100)

src/protocol-v2/LedgityYieldVault.sol#L407-L469


 - [ ] ID-70
Reentrancy in [LToken._beforeTokenTransfer(address,address,uint256)](src/protocol-v1/LToken.sol#L566-L576):
	External calls:
	- [_beforeInvestmentChange(from,true)](src/protocol-v1/LToken.sol#L574)
		- [transfersListeners[i].onLTokenTransfer(from,to,amount)](src/protocol-v1/LToken.sol#L599)
	- [_beforeInvestmentChange(to,true)](src/protocol-v1/LToken.sol#L575)
		- [transfersListeners[i].onLTokenTransfer(from,to,amount)](src/protocol-v1/LToken.sol#L599)
	State variables written after the call(s):
	- [_beforeInvestmentChange(to,true)](src/protocol-v1/LToken.sol#L575)
		- [_balances[account] += amount](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L264)
	[ERC20Upgradeable._balances](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L40) can be used in cross function reentrancies:
	- [ERC20Upgradeable._burn(address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L282-L298)
	- [ERC20Upgradeable._mint(address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L256-L269)
	- [ERC20Upgradeable._transfer(address,address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L227-L245)
	- [ERC20Upgradeable.balanceOf(address)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L106-L108)
	- [_beforeInvestmentChange(to,true)](src/protocol-v1/LToken.sol#L575)
		- [_isClaiming = true](src/protocol-v1/abstracts/InvestUpgradeable.sol#L476)
		- [_isClaiming = false](src/protocol-v1/abstracts/InvestUpgradeable.sol#L478)
	[InvestUpgradeable._isClaiming](src/protocol-v1/abstracts/InvestUpgradeable.sol#L88) can be used in cross function reentrancies:
	- [InvestUpgradeable._beforeInvestmentChange(address,bool)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L445-L488)
	- [_beforeInvestmentChange(to,true)](src/protocol-v1/LToken.sol#L575)
		- [_totalSupply += amount](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L261)
	[ERC20Upgradeable._totalSupply](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L44) can be used in cross function reentrancies:
	- [ERC20Upgradeable._burn(address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L282-L298)
	- [ERC20Upgradeable._mint(address,uint256)](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L256-L269)
	- [ERC20Upgradeable.totalSupply()](node_modules/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol#L99-L101)
	- [_beforeInvestmentChange(to,true)](src/protocol-v1/LToken.sol#L575)
		- [accountsDetails[account].period.timestamp = uint40(block.timestamp)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L421-L423)
		- [accountsDetails[account].period.ref = _aprHistory.getLatestReference()](src/protocol-v1/abstracts/InvestUpgradeable.sol#L424-L425)
		- [accountsDetails[account].virtualBalance = rewards](src/protocol-v1/abstracts/InvestUpgradeable.sol#L483)
	[InvestUpgradeable.accountsDetails](src/protocol-v1/abstracts/InvestUpgradeable.sol#L78) can be used in cross function reentrancies:
	- [InvestUpgradeable._beforeInvestmentChange(address,bool)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L445-L488)
	- [InvestUpgradeable._deepResetInvestmentPeriodOf(address)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L419-L437)
	- [InvestUpgradeable._rewardsOf(address,bool)](src/protocol-v1/abstracts/InvestUpgradeable.sol#L326-L412)

src/protocol-v1/LToken.sol#L566-L576


 - [ ] ID-71
Reentrancy in [LTokenHedera.deposit(uint256,string)](src/protocol-v1/hedera/LTokenHedera.sol#L638-L667):
	External calls:
	- [underlying().transferFrom(_msgSender(),address(this),amount)](src/protocol-v1/hedera/LTokenHedera.sol#L662)
	- [_transferExceedingToFund()](src/protocol-v1/hedera/LTokenHedera.sol#L666)
		- [underlying().transfer(fund,exceedingAmount)](src/protocol-v1/hedera/LTokenHedera.sol#L606)
	State variables written after the call(s):
	- [_transferExceedingToFund()](src/protocol-v1/hedera/LTokenHedera.sol#L666)
		- [usableUnderlyings -= exceedingAmount](src/protocol-v1/hedera/LTokenHedera.sol#L603)
	[LTokenHedera.usableUnderlyings](src/protocol-v1/hedera/LTokenHedera.sol#L152) can be used in cross function reentrancies:
	- [LTokenHedera._transferExceedingToFund()](src/protocol-v1/hedera/LTokenHedera.sol#L592-L607)
	- [LTokenHedera.claimFees()](src/protocol-v1/hedera/LTokenHedera.sol#L1115-L1132)
	- [LTokenHedera.deposit(uint256,string)](src/protocol-v1/hedera/LTokenHedera.sol#L638-L667)
	- [LTokenHedera.instantWithdrawal(uint256)](src/protocol-v1/hedera/LTokenHedera.sol#L704-L759)
	- [LTokenHedera.processBigQueuedRequest(uint256)](src/protocol-v1/hedera/LTokenHedera.sol#L969-L1049)
	- [LTokenHedera.processQueuedRequests()](src/protocol-v1/hedera/LTokenHedera.sol#L834-L959)
	- [LTokenHedera.recoverUnderlying()](src/protocol-v1/hedera/LTokenHedera.sol#L478-L493)
	- [LTokenHedera.repatriate(uint256)](src/protocol-v1/hedera/LTokenHedera.sol#L1094-L1112)
	- [LTokenHedera.usableUnderlyings](src/protocol-v1/hedera/LTokenHedera.sol#L152)

src/protocol-v1/hedera/LTokenHedera.sol#L638-L667


 - [ ] ID-72
Reentrancy in [LedgityYieldVault._withdraw(address,address,address,uint256,uint256)](src/protocol-v2/LedgityYieldVault.sol#L478-L522):
	External calls:
	- [IERC20(address(this)).safeTransferFrom(caller_,feeRecipient,withdrawalFee)](src/protocol-v2/LedgityYieldVault.sol#L502-L506)
	- [_withdrawBuffer(receiver_,netAssets)](src/protocol-v2/LedgityYieldVault.sol#L516)
		- [aaveLendingPool.withdraw(asset(),amountAssets,to)](src/protocol-v2/LedgityYieldVault.sol#L394)
	State variables written after the call(s):
	- [_withdrawBuffer(receiver_,netAssets)](src/protocol-v2/LedgityYieldVault.sol#L516)
		- [lastBufferRewardBalance -= amountAssets](src/protocol-v2/LedgityYieldVault.sol#L396)
	[LedgityYieldVault.lastBufferRewardBalance](src/protocol-v2/LedgityYieldVault.sol#L100) can be used in cross function reentrancies:
	- [LedgityYieldVault._bufferRewards()](src/protocol-v2/LedgityYieldVault.sol#L366-L372)
	- [LedgityYieldVault._depositBuffer(uint256)](src/protocol-v2/LedgityYieldVault.sol#L378-L384)
	- [LedgityYieldVault._withdrawBuffer(address,uint256)](src/protocol-v2/LedgityYieldVault.sol#L393-L397)
	- [LedgityYieldVault.harvestFees()](src/protocol-v2/LedgityYieldVault.sol#L684-L693)
	- [LedgityYieldVault.lastBufferRewardBalance](src/protocol-v2/LedgityYieldVault.sol#L100)

src/protocol-v2/LedgityYieldVault.sol#L478-L522


 - [ ] ID-73
Reentrancy in [LedgityYieldVault.processRequests(uint256[],uint256)](src/protocol-v2/LedgityYieldVault.sol#L729-L788):
	External calls:
	- [IERC20(asset()).safeTransferFrom(liquidityManager,address(this),addedLiquidity)](src/protocol-v2/LedgityYieldVault.sol#L734-L738)
	- [_withdrawBuffer(address(this),neededFromBuffer)](src/protocol-v2/LedgityYieldVault.sol#L768)
		- [aaveLendingPool.withdraw(asset(),amountAssets,to)](src/protocol-v2/LedgityYieldVault.sol#L394)
	- [IERC20(asset()).safeTransfer(request_scope_1.user,request_scope_1.assets)](src/protocol-v2/LedgityYieldVault.sol#L778)
	State variables written after the call(s):
	- [request_scope_1.processed = true](src/protocol-v2/LedgityYieldVault.sol#L780)
	[LedgityYieldVault.withdrawalRequests](src/protocol-v2/LedgityYieldVault.sol#L108) can be used in cross function reentrancies:
	- [LedgityYieldVault.getUserWithdrawalRequests(address,bool,uint256)](src/protocol-v2/LedgityYieldVault.sol#L305-L324)
	- [LedgityYieldVault.getWithdrawalRequestCount()](src/protocol-v2/LedgityYieldVault.sol#L352-L358)
	- [LedgityYieldVault.getWithdrawalRequests(bool,uint256)](src/protocol-v2/LedgityYieldVault.sol#L279-L296)
	- [LedgityYieldVault.getWithdrawalRequestsByIds(uint256[])](src/protocol-v2/LedgityYieldVault.sol#L331-L346)
	- [LedgityYieldVault.processRequests(uint256[],uint256)](src/protocol-v2/LedgityYieldVault.sol#L729-L788)
	- [LedgityYieldVault.requestWithdrawal(uint256)](src/protocol-v2/LedgityYieldVault.sol#L633-L678)
	- [LedgityYieldVault.withdrawalRequests](src/protocol-v2/LedgityYieldVault.sol#L108)

src/protocol-v2/LedgityYieldVault.sol#L729-L788


## uninitialized-local
Impact: Medium
Confidence: Medium
 - [ ] ID-74
[LedgityDataProvider._getFilteredRequests(LedgityDataProvider.WithdrawalRequest[],IERC20,uint256,address,bool,uint256).matchCount](src/protocol-v2/libraries/LedgityDataProvider.sol#L156) is a local variable never initialized

src/protocol-v2/libraries/LedgityDataProvider.sol#L156


 - [ ] ID-75
[LedgityDataProvider._getFilteredRequests(LedgityDataProvider.WithdrawalRequest[],IERC20,uint256,address,bool,uint256).searchCount](src/protocol-v2/libraries/LedgityDataProvider.sol#L157) is a local variable never initialized

src/protocol-v2/libraries/LedgityDataProvider.sol#L157


 - [ ] ID-76
[LedgityYieldVault._withdraw(address,address,address,uint256,uint256).withdrawalFee](src/protocol-v2/LedgityYieldVault.sol#L496) is a local variable never initialized

src/protocol-v2/LedgityYieldVault.sol#L496


 - [ ] ID-77
[HederaTokenService.getTokenCustomFees(address).defaultFixedFees](src/protocol-v1/hedera/lib/HederaTokenService.sol#L441) is a local variable never initialized

src/protocol-v1/hedera/lib/HederaTokenService.sol#L441


 - [ ] ID-78
[HederaTokenService.getTokenInfo(address).defaultTokenInfo](src/protocol-v1/hedera/lib/HederaTokenService.sol#L382) is a local variable never initialized

src/protocol-v1/hedera/lib/HederaTokenService.sol#L382


 - [ ] ID-79
[HederaTokenService.getTokenCustomFees(address).defaultRoyaltyFees](src/protocol-v1/hedera/lib/HederaTokenService.sol#L443) is a local variable never initialized

src/protocol-v1/hedera/lib/HederaTokenService.sol#L443


 - [ ] ID-80
[LedgityYieldVault.processRequests(uint256[],uint256).assetsTotal](src/protocol-v2/LedgityYieldVault.sol#L745) is a local variable never initialized

src/protocol-v2/LedgityYieldVault.sol#L745


 - [ ] ID-81
[LedgityDataProvider.getWithdrawalRequestsByIds(LedgityDataProvider.WithdrawalRequest[],IERC20,uint256,uint256[]).hasFeeReduction](src/protocol-v2/libraries/LedgityDataProvider.sol#L113) is a local variable never initialized

src/protocol-v2/libraries/LedgityDataProvider.sol#L113


 - [ ] ID-82
[LedgityDataProvider._getFilteredRequests(LedgityDataProvider.WithdrawalRequest[],IERC20,uint256,address,bool,uint256).resultIndex](src/protocol-v2/libraries/LedgityDataProvider.sol#L179) is a local variable never initialized

src/protocol-v2/libraries/LedgityDataProvider.sol#L179


 - [ ] ID-83
[HederaTokenService.getTokenCustomFees(address).defaultFractionalFees](src/protocol-v1/hedera/lib/HederaTokenService.sol#L442) is a local variable never initialized

src/protocol-v1/hedera/lib/HederaTokenService.sol#L442


 - [ ] ID-84
[LedgityYieldVault.requestWithdrawal(uint256).withdrawalFee](src/protocol-v2/LedgityYieldVault.sol#L641) is a local variable never initialized

src/protocol-v2/LedgityYieldVault.sol#L641


 - [ ] ID-85
[VaultLiquidityModule._computeFeeData().performanceFeeAssets](src/protocol-v2/modules/VaultLiquidityModule.sol#L301) is a local variable never initialized

src/protocol-v2/modules/VaultLiquidityModule.sol#L301


 - [ ] ID-86
[HederaTokenService.getNonFungibleTokenInfo(address,int64).defaultTokenInfo](src/protocol-v1/hedera/lib/HederaTokenService.sol#L408) is a local variable never initialized

src/protocol-v1/hedera/lib/HederaTokenService.sol#L408


 - [ ] ID-87
[HederaTokenService.getTokenExpiryInfo(address).defaultExpiryInfo](src/protocol-v1/hedera/lib/HederaTokenService.sol#L1132) is a local variable never initialized

src/protocol-v1/hedera/lib/HederaTokenService.sol#L1132


 - [ ] ID-88
[LedgityDataProvider._getFilteredRequests(LedgityDataProvider.WithdrawalRequest[],IERC20,uint256,address,bool,uint256).hasFeeReduction](src/protocol-v2/libraries/LedgityDataProvider.sol#L195) is a local variable never initialized

src/protocol-v2/libraries/LedgityDataProvider.sol#L195


 - [ ] ID-89
[HederaTokenService.getFungibleTokenInfo(address).defaultTokenInfo](src/protocol-v1/hedera/lib/HederaTokenService.sol#L355) is a local variable never initialized

src/protocol-v1/hedera/lib/HederaTokenService.sol#L355


 - [ ] ID-90
[HederaTokenService.getTokenKey(address,uint256).defaultKeyValueInfo](src/protocol-v1/hedera/lib/HederaTokenService.sol#L1068) is a local variable never initialized

src/protocol-v1/hedera/lib/HederaTokenService.sol#L1068


## write-after-write
Impact: Medium
Confidence: High
 - [ ] ID-91
[InvestUpgradeable._isClaiming](src/protocol-v1/abstracts/InvestUpgradeable.sol#L88) is written in both
	[_isClaiming = true](src/protocol-v1/abstracts/InvestUpgradeable.sol#L476)
	[_isClaiming = false](src/protocol-v1/abstracts/InvestUpgradeable.sol#L478)

src/protocol-v1/abstracts/InvestUpgradeable.sol#L88


