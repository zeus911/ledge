use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 2); 

my $pwd = cwd();

$ENV{TEST_LEDGE_REDIS_DATABASE} ||= 1;
$ENV{TEST_USE_RESTY_CORE} ||= 'nil';

our $HttpConfig = qq{
    lua_package_path "$pwd/../lua-resty-redis-connector/lib/?.lua;$pwd/../lua-resty-qless/lib/?.lua;$pwd/../lua-resty-http/lib/?.lua;$pwd/../lua-resty-cookie/lib/?.lua;$pwd/lib/?.lua;;";
    init_by_lua "
        local use_resty_core = $ENV{TEST_USE_RESTY_CORE}
        if use_resty_core then
            require 'resty.core'
        end
        ledge_mod = require 'ledge.ledge'
        ledge = ledge_mod:new()
        ledge:config_set('redis_database', $ENV{TEST_LEDGE_REDIS_DATABASE})
        ledge:config_set('upstream_host', '127.0.0.1')
        ledge:config_set('upstream_port', 1984)
        redis_socket = '$ENV{TEST_LEDGE_REDIS_SOCKET}'
    ";
    init_worker_by_lua "
        ledge:run_workers()
    ";
};

no_long_string();
run_tests();

__DATA__
=== TEST 1: Short read timeout results in error 524.
--- http_config eval: $::HttpConfig
--- config
location /upstream_prx {
    rewrite ^(.*)_prx$ $1 break;
    content_by_lua '
        ledge:config_set("upstream_read_timeout", 100)
        ledge:run()
    ';
}
location /upstream {
    content_by_lua '
        ngx.sleep(1)
        ngx.say("OK")
    ';
}
--- request
GET /upstream_prx
--- error_code: 524
--- response_body


=== TEST 2: No upstream results in a 503.
--- http_config eval: $::HttpConfig
--- config
location /upstream_prx {
    rewrite ^(.*)_prx$ $1 break;
    content_by_lua '
        ledge:config_set("upstream_host", "")
        ledge:run()
    ';
}
--- request
GET /upstream_prx
--- error_code: 503
--- response_body

