############################
# IAM ROLE FOR LAMBDA
############################

resource "aws_iam_role" "lambda_role" {
  name = "backup-tagger-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

############################
# CUSTOM POLICY
############################

resource "aws_iam_policy" "tagging_policy" {

  name = "lambda-backup-tagging-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [

      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",
          "ec2:CreateTags"
        ],
        Resource = "*"
      },

      {
        Effect = "Allow",
        Action = [
          "rds:DescribeDBInstances",
          "rds:AddTagsToResource"
        ],
        Resource = "*"
      }

    ]
  })
}

resource "aws_iam_role_policy_attachment" "tagging_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.tagging_policy.arn
}

############################
# LAMBDA FUNCTION
############################

resource "aws_lambda_function" "backup_tagger" {

  function_name = "backup-resource-tagger"

  filename         = "lambda_backup_tagger.zip"
  source_code_hash = filebase64sha256("lambda_backup_tagger.zip")

  handler = "lambda_backup_tagger.lambda_handler"
  runtime = "python3.12"

  role = aws_iam_role.lambda_role.arn

  timeout = 30
}

############################
# EVENTBRIDGE SCHEDULE
############################

resource "aws_cloudwatch_event_rule" "lambda_schedule" {

  name                = "backup-tagging-schedule"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {

  rule = aws_cloudwatch_event_rule.lambda_schedule.name
  arn  = aws_lambda_function.backup_tagger.arn
}

############################
# PERMISSION FOR EVENTBRIDGE
############################

resource "aws_lambda_permission" "allow_eventbridge" {

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_tagger.function_name
  principal     = "events.amazonaws.com"

  source_arn = aws_cloudwatch_event_rule.lambda_schedule.arn
}
