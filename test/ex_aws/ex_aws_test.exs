defmodule ExAwsTest do
  use ExUnit.Case, async: true

  @endpoint_uri System.get_env("AWS_ENDPOINT_URL", "http://127.0.0.1:8000") |> URI.parse()

  @config [
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID", "fake-id"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY", "fake-key"),
    scheme: "#{@endpoint_uri.scheme}://",
    host: @endpoint_uri.host,
    port: @endpoint_uri.port
  ]

  # Skip until I figure out what the issue here is
  @tag :skip
  test "basic S3 operation works" do
    op = %ExAws.Operation.S3{
      body: "",
      bucket: "",
      headers: %{},
      http_method: :get,
      params: [],
      parser: & &1,
      path: "/",
      resource: "",
      service: :s3,
      stream_builder: nil
    }

    assert {:ok, %{body: _}} = ExAws.request(op)
  end

  test "nonexistent bucket" do
    op = %ExAws.Operation.S3{
      body: "",
      bucket: "no-way",
      headers: %{},
      http_method: :head,
      params: [],
      parser: & &1,
      path: "/",
      resource: "",
      service: :s3,
      stream_builder: nil
    }

    {:error, {:http_error, status_code, _headers}} = ExAws.request(op, @config)

    assert status_code == 404
  end

  test "basic json operation works" do
    TelemetryHelper.attach_telemetry([:ex_aws, :request])

    op = %ExAws.Operation.JSON{
      http_method: :post,
      service: :dynamodb,
      headers: [
        {"x-amz-target", "DynamoDB_20120810.ListTables"},
        {"content-type", "application/x-amz-json-1.0"}
      ]
    }

    assert {:ok, %{"TableNames" => _}} = ExAws.request(op)

    assert_receive {[:ex_aws, :request, :start], %{system_time: _},
                    %{
                      attempt: 1,
                      options: [],
                      request_body: "{}"
                    }}

    assert_receive {[:ex_aws, :request, :stop], %{duration: _},
                    %{
                      options: [],
                      attempt: 1,
                      request_body: "{}",
                      result: :ok,
                      response_body: "{\"TableNames\":[]}"
                    }}
  end

  test "json operation with differently named service" do
    op = %ExAws.Operation.JSON{
      before_request: nil,
      data: %{},
      headers: [
        {"x-amz-target", "DynamoDBStreams_20120810.ListStreams"},
        {"content-type", "application/x-amz-json-1.0"}
      ],
      http_method: :post,
      params: %{},
      parser: & &1,
      path: "/",
      service: :dynamodb_streams,
      stream_builder: nil
    }

    assert {:ok, %{"Streams" => _}} = ExAws.request(op)
  end

  test "custom telemetry options" do
    TelemetryHelper.attach_telemetry([:ex_aws, :custom_request])

    op = %ExAws.Operation.JSON{
      http_method: :post,
      service: :dynamodb,
      headers: [
        {"x-amz-target", "DynamoDB_20120810.ListTables"},
        {"content-type", "application/x-amz-json-1.0"}
      ]
    }

    options = [telemetry_event: [:ex_aws, :custom_request], telemetry_options: [name: :sample]]

    assert {:ok, %{"TableNames" => _}} = ExAws.request(op, options)

    assert_receive {[:ex_aws, :custom_request, :start], %{system_time: _},
                    %{
                      attempt: 1,
                      options: [name: :sample]
                    }}

    assert_receive {[:ex_aws, :custom_request, :stop], %{duration: _},
                    %{
                      options: [name: :sample],
                      attempt: 1,
                      result: :ok
                    }}
  end

  test "telemetry operation and service" do
    TelemetryHelper.attach_telemetry([:ex_aws, :custom_request])

    op = %ExAws.Operation.JSON{
      http_method: :post,
      service: :dynamodb,
      headers: [
        {"x-amz-target", "DynamoDB_20120810.ListTables"},
        {"content-type", "application/x-amz-json-1.0"}
      ]
    }

    options = [telemetry_event: [:ex_aws, :custom_request]]

    assert {:ok, %{"TableNames" => _}} = ExAws.request(op, options)

    assert_receive {[:ex_aws, :custom_request, :start], %{system_time: _},
                    %{
                      attempt: 1,
                      operation: "DynamoDB_20120810.ListTables",
                      service: :dynamodb,
                      options: []
                    }}

    assert_receive {[:ex_aws, :custom_request, :stop], %{duration: _},
                    %{
                      attempt: 1,
                      operation: "DynamoDB_20120810.ListTables",
                      service: :dynamodb,
                      options: [],
                      result: :ok
                    }}
  end

  test "invalid request" do
    TelemetryHelper.attach_telemetry([:ex_aws, :request])

    op = %ExAws.Operation.JSON{
      http_method: :post,
      service: :dynamodb,
      headers: [
        {"x-amz-target", "DynamoDB_20120810.CreateTable"},
        {"content-type", "application/x-amz-json-1.0"}
      ]
    }

    assert {:error, {"ValidationException", _}} = ExAws.request(op)

    assert_receive {[:ex_aws, :request, :start], %{system_time: _},
                    %{
                      options: [],
                      attempt: 1,
                      request_body: "{}"
                    }}

    assert_receive {[:ex_aws, :request, :stop], %{duration: _},
                    %{
                      options: [],
                      attempt: 1,
                      request_body: "{}",
                      result: :error,
                      error:
                        ~s({"__type":"ValidationException","message":"The parameter 'TableName' is required but was not present in the request"})
                    }}
  end
end
