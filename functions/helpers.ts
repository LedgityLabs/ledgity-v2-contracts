import { formatUnits, parseUnits } from 'viem';

export const DAYS_PER_YEAR = 365;
// RAY has 27 decimals; rates are expressed with 2 decimal precision, so the effective base is 25
const RAY_RATE_BASE_DECIMALS = 25;

function snapRateToIntegerTolerance(ratePercent: number): number {
	const roundedRate = Math.round(ratePercent);
	return Math.abs(ratePercent - roundedRate) <= 1e-5 ? roundedRate : ratePercent;
}

export function aprToApy(aprPercent: number): number {
	return snapRateToIntegerTolerance(
		(Math.pow(1 + aprPercent / 100 / DAYS_PER_YEAR, DAYS_PER_YEAR) - 1) * 100
	);
}

export function apyToApr(apyPercent: number): number {
	return snapRateToIntegerTolerance(
		(Math.pow(1 + apyPercent / 100, 1 / DAYS_PER_YEAR) - 1) * DAYS_PER_YEAR * 100
	);
}

export function rayAprToApyPercent(apr: bigint): number {
	return aprToApy(Number(formatUnits(apr, RAY_RATE_BASE_DECIMALS)));
}

export function rayAprToRayApy(apr: bigint): bigint {
	return parseUnits(rayAprToApyPercent(apr).toFixed(7), RAY_RATE_BASE_DECIMALS);
}

export function apyToRayApr(apyPercent: number): bigint {
	return parseUnits(apyToApr(apyPercent).toFixed(7), RAY_RATE_BASE_DECIMALS);
}
