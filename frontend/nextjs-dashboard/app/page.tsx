type ClusterData = {
  connectedClients: number;
  runningCoreNodes: number;
  runningReplicantNodes: number;
  clusterStatus: string;
  autoScalingEvents: string[];
  cpuUsagePercent: number;
  nlbDnsName: string;
};

async function getData(): Promise<ClusterData> {
  const res = await fetch("http://localhost:3000/api/cluster", { cache: "no-store" });
  return res.json();
}

function Card({ title, value }: { title: string; value: string | number }) {
  return (
    <div className="rounded-xl border border-slate-800 bg-slate-900 p-5">
      <p className="text-sm text-slate-400">{title}</p>
      <p className="mt-2 text-2xl font-semibold">{value}</p>
    </div>
  );
}

export default async function Home() {
  const data = await getData();

  return (
    <main className="mx-auto max-w-6xl p-8">
      <h1 className="text-3xl font-bold">EMQX Cluster Demo Dashboard</h1>
      <p className="mt-2 text-slate-400">Interview presentation view for AWS + Terraform + EMQX architecture.</p>

      <div className="mt-6 grid gap-4 md:grid-cols-3">
        <Card title="Connected Clients" value={data.connectedClients} />
        <Card title="Running Core Nodes" value={data.runningCoreNodes} />
        <Card title="Running Replicant Nodes" value={data.runningReplicantNodes} />
        <Card title="Cluster Status" value={data.clusterStatus} />
        <Card title="Replicant CPU %" value={data.cpuUsagePercent} />
        <Card title="NLB DNS" value={data.nlbDnsName} />
      </div>

      <section className="mt-6 rounded-xl border border-slate-800 bg-slate-900 p-5">
        <h2 className="text-xl font-semibold">Recent Auto Scaling Events</h2>
        <ul className="mt-3 list-disc space-y-1 pl-5 text-slate-300">
          {data.autoScalingEvents.map((event) => (
            <li key={event}>{event}</li>
          ))}
        </ul>
      </section>
    </main>
  );
}
