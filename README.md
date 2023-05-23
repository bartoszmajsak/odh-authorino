# Open Data Hub protected with Authorino Ext-Authz

This is a Proof of Concept of protecting [Open Data Hub](https://opendatahub.io/) with [Authorino](https://github.com/kuadrant/authorino) external authorization on an OpenShift cluster.

## Target architecture

![Architecture](./architecture.png)

## Try

### Requirements

- OpenShift cluster with the following operators installed:
  - Kiali
  - Jaeger
  - OpenShift Service Mesh (OSSM)
  - Open Data Hub
  - Authorino
- CLI tools
  - `kubectl`
  - `oc`
  - `jq`

### Setup

<details>
  <summary>① Clone the repo</summary>

  ```sh
  git clone git@github.com:guicassolato/odh-authorino.git && cd odh-authorino
  ```
</details>

<details>
  <summary>② Store the OpenShift cluster domain in the shell</summary>

  <br/>

  > ⚠️ This step is important as well for other parts of the tutorial further below. Do not skip it.

  ```sh
  export CLUSTER_DOMAIN=gui-rhods.2hfs.s1.devshift.org
  ```
</details>

<details>
  <summary>③ Login to the cluster</summary>

  ```sh
  oc login --token=... --server=https://api.$CLUSTER_DOMAIN:6443
  ```
</details>

<details>
  <summary>④ Configure the service mesh control plane</summary>

  ```sh
  make smcp | kubectl apply -f -
  sleep 4 # to prevent kubectl wait from failing
  kubectl wait --for condition=Ready smcp/basic --timeout 300s -n istio-system
  ```
</details>

<details>
  <summary>⑤ Deploy Authorino</summary>

  ```sh
  export AUTH_NS=authorino
  make authorino | kubectl apply -f -
  ```

  Patch the service mesh configuration to register the new external authorization provider:

  ```sh
  kubectl patch smcp/basic -n istio-system --type merge -p "{\"spec\":{\"techPreview\":{\"meshConfig\":{\"extensionProviders\":[{\"name\":\"auth-provider\",\"envoyExtAuthzGrpc\":{\"service\":\"authorino-authorino-authorization.$AUTH_NS.svc.cluster.local\",\"port\":50051}}]}}}}"
  ```

  Avoid injecting the sidecar proxy in the Authorino container: _(Optional)_

  ```sh
  kubectl wait --for condition=Available deployment/authorino --timeout 300s -n authorino
  kubectl patch deployment/authorino -n authorino --type merge -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"sidecar.istio.io/inject\":\"false\"}}}}}"
  ```
</details>

### Try with a sample application first

<details>
  <summary>① Deploy the sample application (Talker API)</summary>

  <br/>

  ```sh
  endpoint=$(kubectl -n default run oidc-config --attach --rm --restart=Never -q --image=curlimages/curl -- https://kubernetes.default.svc/.well-known/oauth-authorization-server -sS -k)
  export AUTH_ENDPOINT=$(echo $endpoint | jq -r .authorization_endpoint)
  make talker-api | kubectl apply -f -
  ```
</details>

<details>
  <summary>② Test endpoints of the Talker API protected behind Authorino</summary>

  <br/>

  Try the API without an access token:

  ```sh
  curl http://talker-api.apps.$CLUSTER_DOMAIN -I
  # HTTP/1.1 302 Found
  # location: https://oauth-openshift.apps....
  ```

  Try the API as the same user logged in to OpenShift cluster in the terminal:

  > The expected result is `403 Forbidden` because the token does not have the required scope, nor the user is bound to a role that grants permission.

  ```sh
  curl -H "Authorization: Bearer $(oc whoami -t)" http://talker-api.apps.$CLUSTER_DOMAIN -I
  # HTTP/1.1 403 Forbidden
  ```

  Check that the callback endpoint skips the authorization:

  > This will be useful in another step further below, when simulating a webapp (frontend + backend for frontend) that consumes the API.

  ```sh
  curl http://talker-api.apps.$CLUSTER_DOMAIN/oauth/callback -I
  # HTTP/1.1 200 OK
  ```
</details>

<details>
  <summary>③ Try the API as a webapp that also runs inside the cluster</summary>

  <br/>

  The Talker API itself will be used as the **backend for frontend** of the webapp, and the Internet browser and terminal as the **frontend**. The codes 🅱 and 🅵 will be used to identify in the commands below which of these components respectively the command simulates.

  <br/>

  Request a protected endpoint of the API in the browser:

  ```sh
  open http://talker-api.apps.$CLUSTER_DOMAIN
  ```

  Login as a user of the OpenShift cluster and delegate powers to the  service account.

  🅱 Finish the OAuth flow in the terminal:

  ```sh
  export TOKEN_ENDPOINT=$(echo $endpoint | jq -r .token_endpoint)
  export OAUTH_CLIENT_SECRET=$(kubectl get $(kubectl get secrets -n talker-api -o name | grep talker-api-bff-token) -n talker-api -o jsonpath='{.data.token}' | base64 -d)
  export ACCESS_TOKEN=$(curl -d client_id=system:serviceaccount:talker-api:talker-api-bff \
      -d client_secret=$OAUTH_CLIENT_SECRET \
      -d redirect_uri=http://talker-api.apps.${CLUSTER_DOMAIN}/oauth/callback \
      -d grant_type=authorization_code \
      -d code=… \
      -d state=… \
      $TOKEN_ENDPOINT | jq -r .access_token)
  ```

  🅵 Send a request to the API as the webapp:

  ```sh
  curl -H "Authorization: Bearer $ACCESS_TOKEN" http://talker-api.apps.$CLUSTER_DOMAIN -I
  # HTTP/1.1 200 OK
  ```
</details>

<details>
  <summary>④ Try the API as the <code>talker-api-bff</code> SA itself (without delegation)</summary>

  <br/>

  Request a short-lived token for the SA:

  > This step could be replaced by other methods for the application to obtain the token, such as volume projection.

  ```sh
  export SA_TOKEN=$(kubectl create --raw /api/v1/namespaces/talker-api/serviceaccounts/talker-api-bff/token -f -<<EOF | jq -r .status.token
  { "apiVersion": "authentication.k8s.io/v1", "kind": "TokenRequest", "spec": { "expirationSeconds": 600 } }
  EOF
  )
  ```

  Send a GET request to the API:

  ```sh
  curl -H "Authorization: Bearer $SA_TOKEN" http://talker-api.apps.$CLUSTER_DOMAIN -I
  # HTTP/1.1 200 OK
  ```

  Send a POST request to the API:

  ```sh
  curl -H "Authorization: Bearer $SA_TOKEN" http://talker-api.apps.$CLUSTER_DOMAIN -I -X POST
  # HTTP/1.1 403 Forbidden
  ```
</details>

### Try the Open Data Hub protected with Authorino

TODO(@guicassolato)

### Cleanup

```sh
make authorino | kubectl delete -f -
make talker-api | kubectl delete -f -
make smcp | kubectl delete -f -
```
