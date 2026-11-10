import {AsyncLocalStorage} from "node:async_hooks";

/** Internal opt-in measurements only: no principal, financial data, cache or wire
 * fields. Async context isolates simultaneous emulator profiling requests. */
const context = new AsyncLocalStorage<Record<string, {calls: number; milliseconds: number}>>();
function add(stage: string, began: number) {
  const current = context.getStore();
  if (current) {const value = current[stage] ??= {calls: 0, milliseconds: 0};value.calls++;value.milliseconds += performance.now() - began;}
}
export async function profileSettlementRead<T>(run: () => Promise<T>) {
  const stages: Record<string, {calls: number; milliseconds: number}> = {};
  const result = await context.run(stages, run);return {result, stages};
}
export async function settlementReadStage<T>(stage: string, run: () => Promise<T>): Promise<T> {
  if (!context.getStore()) return run();const began = performance.now();try {return await run();} finally {add(stage, began);}
}
export function settlementReadStageSync<T>(stage: string, run: () => T): T {
  if (!context.getStore()) return run();const began = performance.now();try {return run();} finally {add(stage, began);}
}
