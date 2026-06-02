data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance_role" {
  name               = "${var.project_name}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "route53_read" {
  statement {
    sid     = "Route53Read"
    effect  = "Allow"
    actions = ["route53:Get*", "route53:List*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "route53_read" {
  name   = "${var.project_name}-route53-read"
  policy = data.aws_iam_policy_document.route53_read.json
}

resource "aws_iam_role_policy_attachment" "route53_read" {
  role       = aws_iam_role.instance_role.name
  policy_arn = aws_iam_policy.route53_read.arn
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.instance_role.name
}
