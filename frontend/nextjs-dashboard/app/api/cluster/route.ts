import { NextResponse } from "next/server";

export async function GET() {
  return NextResponse.json({
    connectedClients: 15,
    runningCoreNodes: 3,
    runningReplicantNodes: 2,
    clusterStatus: "Healthy",
    autoScalingEvents: [
      "Scale out: launched replicant-2 (CPU > 40%)",
      "Stable: 2 replicants in service"
    ],
    cpuUsagePercent: 43,
    nlbDnsName: "emqx-interview-nlb.ap-south-1.elb.amazonaws.com"
  });
}
