data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "emqx_ec2" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.project_name}-ec2-role"
  })
}

resource "aws_iam_role_policy_attachment" "emqx_ec2_ssm" {
  role       = aws_iam_role.emqx_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "emqx_ec2_ssm_cluster" {
  name = "${var.project_name}-ec2-ssm-cluster"
  role = aws_iam_role.emqx_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
        ]
        Resource = [
          aws_ssm_parameter.core_private_ip.arn,
          aws_ssm_parameter.cluster_seeds.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
        ]
        Resource = [
          aws_ssm_parameter.core_private_ip.arn,
          aws_ssm_parameter.cluster_seeds.arn,
        ]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "emqx_ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.emqx_ec2.name
}
