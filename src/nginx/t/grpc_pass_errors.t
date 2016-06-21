# Copyright (C) Endpoints Server Proxy Authors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
################################################################################
#
use strict;
use warnings;

################################################################################

BEGIN { use FindBin; chdir($FindBin::Bin); }

use ApiManager;   # Must be first (sets up import path to the Nginx test module)
use Test::Nginx;  # Imports Nginx's test module
use Test::More;   # And the test framework
use HttpServer;

################################################################################

# Port assignments
my $Http2NginxPort = 8080;
my $ServiceControlPort = 8081;
my $HttpBackendPort = 8083;
my $GrpcBackendPort = 8082;
my $GrpcFallbackPort = 8085;

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(4);

$t->write_file('service.pb.txt', ApiManager::get_grpc_test_service_config . <<"EOF");
control {
  environment: "http://127.0.0.1:${ServiceControlPort}"
}
system_parameters {
  rules {
    selector: "test.grpc.Test.Echo"
    parameters {
      name: "api_key"
      http_header: "x-api-key"
    }
  }
}
EOF

$t->write_file_expand('nginx.conf', <<"EOF");
%%TEST_GLOBALS%%
daemon off;
events {
  worker_connections 32;
}
http {
  %%TEST_GLOBALS_HTTP%%
  server {
    listen 127.0.0.1:${Http2NginxPort} http2;
    server_name localhost;
    location / {
      endpoints {
        api service.pb.txt;
        on;
      }
      grpc_pass {
        proxy_pass http://127.0.0.1:${HttpBackendPort}/;
      }
      grpc_backend_address_fallback 127.0.0.2:${GrpcFallbackPort};
    }
  }
}
EOF

$t->run_daemon(\&service_control, $t, $ServiceControlPort, 'requests.log');
$t->run_daemon(\&ApiManager::grpc_test_server, $t, "127.0.0.1:${GrpcBackendPort}");
is($t->waitforsocket("127.0.0.1:${ServiceControlPort}"), 1, 'Service control socket ready.');
is($t->waitforsocket("127.0.0.1:${GrpcBackendPort}"), 1, 'GRPC test server socket ready.');
$t->run();
is($t->waitforsocket("127.0.0.1:${Http2NginxPort}"), 1, 'Nginx socket ready.');

################################################################################
my $test_results = &ApiManager::run_grpc_test($t, <<"EOF");
server_addr: "127.0.0.1:${Http2NginxPort}"
plans {
  echo {
    call_config {
      api_key: "this-is-an-api-key"
    }
    request {
      return_status {
        code: 2
        details: "Error propagation test"
      }
      text: "Hello, world!"
    }
  }
}
plans {
  echo {
    call_config {
      api_key: "this-is-an-api-key"
    }
    request {
      return_status {
        code: 3
        details: "Another propagation test"
      }
      text: "Hello, world!"
    }
  }
}
plans {
  echo {
    call_config {
      api_key: "this-is-an-api-key"
    }
    request {
      return_status {
        code: 4
        details: "A long error message.  Like, really ridiculously detailed, the kind of thing you might expect if someone put a Java stack with nested thrown exceptions into an error message, which does actually happen so it is important to make sure long messages are passed through correctly by the grpc_pass implementation within nginx.  Any string longer than 128 bytes should suffice to give us confidence that the HTTP/2 header length encoding implementation at least tries to do the right thing; this one should do just fine."
      }
      text: "Hello, world!"
    }
  }
}
EOF

$t->stop_daemons();

my $test_results_expected = <<'EOF';
results {
  status {
    code: 2
    details: "Error propagation test"
  }
}
results {
  status {
    code: 3
    details: "Another propagation test"
  }
}
results {
  status {
    code: 4
    details: "A long error message.  Like, really ridiculously detailed, the kind of thing you might expect if someone put a Java stack with nested thrown exceptions into an error message, which does actually happen so it is important to make sure long messages are passed through correctly by the grpc_pass implementation within nginx.  Any string longer than 128 bytes should suffice to give us confidence that the HTTP/2 header length encoding implementation at least tries to do the right thing; this one should do just fine."
  }
}
EOF

is($test_results, $test_results_expected, 'Client tests completed as expected.');

################################################################################

sub service_control {
  my ($t, $port, $file) = @_;
  my $server = HttpServer->new($port, $t->testdir() . '/' . $file)
    or die "Can't create test server socket: $!\n";

  $server->on_sub('POST', '/v1/services/endpoints-grpc-test.cloudendpointsapis.com:check', sub {
    my ($headers, $body, $client) = @_;
    print $client <<'EOF';
HTTP/1.1 200 OK
Connection: close

EOF
  });

  $server->run();
}

################################################################################