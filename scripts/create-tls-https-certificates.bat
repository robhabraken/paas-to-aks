@ECHO OFF
IF "%1" == "" GOTO :MissingParam

    SET certificatePath=..\sitecore\k8s\%1\secrets\tls

    IF NOT EXIST mkcert.exe powershell Invoke-WebRequest https://github.com/FiloSottile/mkcert/releases/download/v1.4.1/mkcert-v1.4.1-windows-amd64.exe -UseBasicParsing -OutFile mkcert.exe
    mkcert -install

    mkcert -cert-file %certificatePath%\global-cm\tls.crt -key-file %certificatePath%\global-cm\tls.key "cm.globalhost"
    mkcert -cert-file %certificatePath%\global-cd\tls.crt -key-file %certificatePath%\global-cd\tls.key "cd.globalhost"
    mkcert -cert-file %certificatePath%\global-id\tls.crt -key-file %certificatePath%\global-id\tls.key "id.globalhost"

    DEL /Q mkcert.exe

    GOTO :End

:MissingParam

    ECHO Missing paramater Topology
    GOTO :End

:End