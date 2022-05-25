envCode=${envCode:-"${1}"}
location=${location:-"${2}"}


  DEPLOYMENT_SCRIPT="az deployment sub create -l $location \
    -n $envCode-fapp-dev \
    -f ./functionappTest.bicep \
    -p  \
      environmentCode=$envCode \
      location=$location"
  $DEPLOYMENT_SCRIPT