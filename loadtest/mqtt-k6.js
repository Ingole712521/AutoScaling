import { sleep } from "k6";
import mqtt from "k6/x/mqtt";

const mqttHost = __ENV.MQTT_HOST || "localhost";
const vus = Number(__ENV.VUS || 1000);
const duration = __ENV.DURATION || "10m";

export const options = {
  vus,
  duration,
};

export default function () {
  const clientId = `k6-client-${__VU}-${__ITER}`;
  const client = mqtt.Client({
    brokers: [`tcp://${mqttHost}:1883`],
    clientId,
    timeout: "10s",
  });

  client.connect();
  client.publish("loadtest/topic", JSON.stringify({ vu: __VU, iter: __ITER }), 0);
  client.disconnect();

  sleep(1);
}
