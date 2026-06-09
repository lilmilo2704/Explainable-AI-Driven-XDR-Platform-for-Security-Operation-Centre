# Recommended Workflow - Source Text

```text
Recommended flow

1. Build the system skeleton locally

Dockerize your platform
include frontend, backend, database, ML service, and Wazuh central components
verify the stack works in a controlled local environment first

2. Deploy the stack to a cloud server

deploy the Dockerized platform to a VM or cloud host
expose the required ports securely
confirm the Wazuh manager is reachable from your lab endpoints

3. Install agents on lab endpoints

install Wazuh agents on the machines you want to monitor
configure each agent to connect to your cloud-hosted manager
verify registration, heartbeat, and basic log flow

4. Prepare the lab scenarios

set up your endpoints with their intended roles, such as web server, auth server, database server, and user workstation
enable the logs you need before any attack simulation starts

5. Run controlled attack simulations

execute the selected attack scenarios in the lab
let agents and servers generate telemetry during the attacks
collect the resulting logs, alerts, and correlated evidence

6. Build datasets from the collected data

export and organize the logs
label the attack windows and normal windows
preprocess them into the format needed for model training

7. Train baseline models

build the first usable AI models from the collected and public data
integrate them back into the platform early

8. Iterate

rerun attacks if needed
improve log quality, features, labels, and model performance
refine the app based on real outputs
```
