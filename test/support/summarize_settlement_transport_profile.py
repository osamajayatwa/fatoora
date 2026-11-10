"""Summarize synthetic SDK observations, not a Firestore bill or cloud SLA."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / "output/phase2b13"


def percentile(values, p):
    values = sorted(values)
    return round(values[max(0, math.ceil(len(values) * p) - 1)], 3) if values else None


def distribution(values):
    return {"samples": len(values), "p50": percentile(values, .5), "p95": percentile(values, .95), "maximum": max(values) if values else None}


def summarize(records):
    completed = [r for r in records if "pdf" in r]
    if not completed:
        return {"completed": False, "outcomes": [{"error": r["error"], "elapsedMillis": r.get("millis"),
            "successfulDeliveriesBeforeFailure": len(r["requests"]), "chargedAdmissionReadUnits": r["chargedReadWork"]} for r in records]}
    all_calls = [m for r in completed for m in [*r["requests"], r["pdf"]]]
    stages = sorted({s for r in completed for s in r["requests"][0].get("stages", {})})
    sums = lambda key: [sum(m[key] for m in [*r["requests"], r["pdf"]]) for r in completed]
    return {
        "completed": True, "runs": len(completed), "logicalPages": completed[0]["pages"], "deliveries": len(completed[0]["requests"]),
        "firstDeliveryMillis": distribution([r["requests"][0]["millis"] for r in completed]),
        "subsequentDeliveryMillis": distribution([m["millis"] for r in completed for m in r["requests"][1:]]),
        "pdfPermissionMillis": distribution([r["pdf"]["millis"] for r in completed]),
        "totalMillis": distribution([r["totalMillis"] for r in completed]),
        "documentReadResultsPerRun": sums("documentReads"),
        "estimatedReadOperationUnitsPerRun": [a+b for a,b in zip(sums("minimumDocumentReadUnits"), sums("aggregateReadUnits"))],
        "queryRPCsPerRun": sums("queries"), "aggregateRPCsPerRun": sums("aggregateQueries"),
        "pointGetRPCsPerRun": sums("documentGets"), "batchGetRPCsPerRun": sums("getAllCalls"),
        "authProviderCallsPerRun": [r["authCalls"] for r in completed],
        "responseJsonBytesPerRun": sums("responseBytes"), "maximumResponseJsonBytes": max(m["responseBytes"] for m in all_calls),
        "firstResponseJsonBytes": [r["requests"][0]["responseBytes"] for r in completed],
        "responseSerializationMillisPerRun": sums("responseSerializationMillis"),
        "chargedAdmissionReadUnits": [r["chargedReadWork"] for r in completed],
        "retainedSerializedBytes": completed[0]["retainedBytes"],
        "observedHeapBytes": max((m.get("heapUsedBytes", 0) for m in all_calls)),
        "observedRssBytes": max((m.get("rssBytes", 0) for m in all_calls)),
        "initialStagesMillis": {s: distribution([r["requests"][0]["stages"][s]["milliseconds"] for r in completed]) for s in stages},
        "subsequentReconciliationCalls": sum(m.get("stages", {}).get("reconciliation", {}).get("calls", 0) for r in completed for m in r["requests"][1:]),
    }


def main():
    summary = {"synthetic": True, "percentiles": "nearest-rank; small startup samples are descriptive only", "modes": {}}
    for mode in ["baseline", "optimized", "optimized-v1", "bounded-memory"]:
        path = DIRECTORY / f"{mode}-performance.json"
        if not path.exists():
            continue
        records = json.loads(path.read_text())["records"]
        summary["modes"][mode] = {str(count): summarize([r for r in records if r["count"] == count]) for count in sorted({r["count"] for r in records})}
    flutter = DIRECTORY / "flutter-delivery.json"
    if flutter.exists():
        records = json.loads(flutter.read_text())["records"]
        summary["dart"] = {str(count): {"runs": len(v := [r for r in records if r["count"] == count]),
            "totalMillis": distribution([r["totalDecodeValidateAssembleMicros"]/1000 for r in v]),
            "decodeMillis": distribution([r["decodeMicros"]/1000 for r in v]),
            "subsequentBatchMillis": distribution([us/1000 for r in v for us in r.get("subsequentBatchMicros", [])])}
            for count in sorted({r["count"] for r in records})}
    (DIRECTORY / "summary.json").write_text(json.dumps(summary, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({mode: {n: {"totalMillis": v.get("totalMillis"), "reads": v.get("documentReadResultsPerRun"), "queries": v.get("queryRPCsPerRun")} for n,v in cases.items()} for mode,cases in summary["modes"].items()}, indent=2))


if __name__ == "__main__":
    main()
