class ApmServerFull < Formula
  desc "Server for shipping APM metrics to Elasticsearch"
  homepage "https://www.elastic.co/"
  url "https://artifacts.elastic.co/downloads/apm-server/apm-server-7.17.4-darwin-x86_64.tar.gz?tap=elastic/homebrew-tap"
  version "7.17.4"
  sha256 "9fd13fe7c5c3a1c24fc4ce7994b83c1919e6944ae2323ec001673969a3b3c4fa"
  conflicts_with "apm-server"
  conflicts_with "apm-server-oss"

  def install
    ["fields.yml", "ingest", "kibana", "module"].each { |d| libexec.install d if File.exist?(d) }
    (libexec/"bin").install "apm-server"
    (etc/"apm-server").install "apm-server.yml"
    (etc/"apm-server").install "modules.d" if File.exist?("modules.d")

    (bin/"apm-server").write <<~EOS
      #!/bin/sh
      exec #{libexec}/bin/apm-server \
        --path.config #{etc}/apm-server \
        --path.home #{libexec} \
        --path.logs #{var}/log/apm-server \
        --path.data #{var}/lib/apm-server \
        "$@"
    EOS
  end

  def post_install
    (var/"lib/apm-server").mkpath
    (var/"log/apm-server").mkpath
  end

  service do
    run opt_bin/"apm-server"
  end

  test do
    require "socket"

    server = TCPServer.new(0)
    port = server.addr[1]
    server.close

    (testpath/"config/apm-server.yml").write <<~EOS
      apm-server:
        host: localhost:#{port}
      output.file:
        path: "#{testpath}/apm-server"
        filename: apm-server
        codec.format:
          string: '%{[transaction]}'
    EOS
    pid = fork do
      exec bin/"apm-server", "-path.config", testpath/"config", "-path.data", testpath/"data"
    end
    sleep 5

    begin
      (testpath/"event").write <<~EOS
        {"metadata": {"process": {"pid": 1234}, "system": {"container": {"id": "container-id"}, "kubernetes": {"namespace": "namespace1", "pod": {"uid": "pod-uid", "name": "pod-name"}, "node": {"name": "node-name"}}}, "service": {"name": "1234_service-12a3", "language": {"name": "ecmascript"}, "agent": {"version": "3.14.0", "name": "elastic-node"}, "framework": {"name": "emac"}}}}
        {"error": {"id": "abcdef0123456789", "timestamp": 1533827045999000, "log": {"level": "custom log level","message": "Cannot read property 'baz' of undefined"}}}
        {"span": {"id": "0123456a89012345", "trace_id": "0123456789abcdef0123456789abcdef", "parent_id": "ab23456a89012345", "transaction_id": "ab23456a89012345", "parent": 1, "name": "GET /api/types", "type": "request.external", "action": "get", "start": 1.845, "duration": 3.5642981, "stacktrace": [], "context": {}}}
        {"transaction": {"trace_id": "01234567890123456789abcdefabcdef", "id": "abcdef1478523690", "type": "request", "duration": 32.592981, "timestamp": 1535655207154000, "result": "200", "context": null, "spans": null, "sampled": null, "span_count": {"started": 0}}}
        {"metricset": {"samples": {"go.memstats.heap.sys.bytes": {"value": 61235}}, "timestamp": 1496170422281000}}
      EOS
      system "curl", "-H", "Content-Type: application/x-ndjson", "-XPOST", "localhost:#{port}/intake/v2/events", "--data-binary", "@#{testpath}/event"
      sleep 5
      s = (testpath/"apm-server/apm-server").read
      assert_match "\"id\":\"abcdef1478523690\"", s
    ensure
      Process.kill "SIGINT", pid
      Process.wait pid
    end
  end
end
