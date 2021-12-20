
EXTERNAL_IP=$(kubectl get service envoy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

for i in {0..99}
do
    NEW_UUID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    header="test---$NEW_UUID"
    echo "FOR: $header"
    for j in {0..4}
    do
        grpcurl -H "x-session-hash: $header" -d '{"content": "sit up straight"}' -proto echo-grpc/api/echo.proto -insecure -v $EXTERNAL_IP:443 api.Echo/Echo | grep "hostname" &
        pids[${i}]=$!
    done

    for pid in ${pids[*]}; do
        wait $pid
    done
done