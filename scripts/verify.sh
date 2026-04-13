#!/usr/bin/env bash
set -euo pipefail

ruby -Ilib test/all_test.rb
bin/rules-ctl validate examples/services/checkout.rb >/tmp/slo-rules-engine-validate.json
bin/rules-ctl generate --provider=datadog examples/services/checkout.rb >/tmp/slo-rules-engine-datadog.json
bin/rules-ctl generate --provider=prometheus_stack examples/services/checkout.rb >/tmp/slo-rules-engine-prometheus-stack.json
bin/rules-ctl generate --provider=prometheus_stack --output-dir=/tmp/slo-rules-engine-generated examples/services/checkout.rb >/tmp/slo-rules-engine-prometheus-stack-output-dir.json
bin/rules-ctl generate-routes --integration=notification_router examples/services/checkout.rb >/tmp/slo-rules-engine-routes.json
bin/rules-ctl candidates examples/telemetry/checkout-signals.json >/tmp/slo-rules-engine-candidates.json
bin/rules-ctl recommend-calculation-basis --observations-per-second=0.01 --failed-observations-to-alert=1 >/tmp/slo-rules-engine-calculation-basis.json
bin/rules-ctl reality-check --provider=datadog --telemetry=examples/telemetry/checkout-signals.json examples/services/checkout.rb >/tmp/slo-rules-engine-reality-check.json

echo "verification ok"
