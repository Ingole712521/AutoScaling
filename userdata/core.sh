#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y curl unzip jq ca-certificates gnupg apt-transport-https lsb-release

# Install EMQX 5.x
curl -fsSL https://assets.emqx.com/scripts/install-emqx-deb.sh | bash
apt-get update -y
apt-get install -y emqx

# Install CloudWatch agent for memory metrics
wget -O /tmp/amazon-cloudwatch-agent.deb https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i /tmp/amazon-cloudwatch-agent.deb

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCFG'
{
  "metrics": {
    "append_dimensions": {
      "AutoScalingGroupName": "${aws:AutoScalingGroupName}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": [
          "mem_used_percent"
        ]
      }
    }
  }
}
CWCFG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

cat > /etc/emqx/emqx.conf <<EOF
node {
  name = "${node_name}"
  cookie = "${node_cookie}"
  role = core
}

cluster {
  discovery_strategy = static
  static {
    seeds = ${seed_nodes}
  }
}

dashboard {
  default_username = "${dashboard_username}"
  default_password = "${dashboard_password}"
}
EOF

systemctl enable emqx
systemctl restart emqx
