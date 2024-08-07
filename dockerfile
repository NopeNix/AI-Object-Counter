FROM tensorflow/tensorflow

# install Requirements
RUN apt update
RUN pip install --upgrade pip
RUN apt install lshw libgl1-mesa-glx -y
RUN pip install tensorflow
RUN pip install tensorflow_hub
RUN pip install matplotlib
RUN pip install kagglehub
RUN pip install opencv-python
RUN pip install torch
RUN pip install pandas
RUN pip install pillow

## INSTALL POWERSHELL
# Define Args for the needed to add the package
ARG PS_VERSION=7.2.4
ARG PS_PACKAGE=powershell_${PS_VERSION}-1.deb_amd64.deb
ARG PS_PACKAGE_URL=https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/${PS_PACKAGE}

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
    # curl is required to grab the Linux package
        curl \
    # less is required for help in powershell
        less \
    # required to setup the locale
        locales \
    # required for SSL
        ca-certificates \
    # Download the Linux package and save it
    && echo ${PS_PACKAGE_URL} \
    && curl -sSL ${PS_PACKAGE_URL} -o /tmp/powershell.deb
# Define Args for the needed to add the package
ARG PS_VERSION=7.2.4
ARG PS_PACKAGE=powershell_${PS_VERSION}-1.deb_amd64.deb
ARG PS_PACKAGE_URL=https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/${PS_PACKAGE}
ARG PS_INSTALL_VERSION=7

# Define ENVs for Localization/Globalization
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    # set a fixed location for the Module analysis cache
    PSModuleAnalysisCachePath=/var/cache/microsoft/powershell/PSModuleAnalysisCache/ModuleAnalysisCache \
    POWERSHELL_DISTRIBUTION_CHANNEL=PSDocker-Ubuntu-22.04

# Install dependencies and clean up
RUN apt-get update \
    && apt-get install --no-install-recommends -y /tmp/powershell.deb \
    && apt-get install --no-install-recommends -y \
    # less is required for help in powershell
        less \
    # required to setup the locale
        locales \
    # required for SSL
        ca-certificates \
        gss-ntlmssp \
        liblttng-ust1 \
    # PowerShell remoting over SSH dependencies
        openssh-client \
    && apt-get dist-upgrade -y \
    && locale-gen $LANG && update-locale \
    # intialize powershell module cache
    # and disable telemetry
    && export POWERSHELL_TELEMETRY_OPTOUT=1 \
    && pwsh \
        -NoLogo \
        -NoProfile \
        -Command " \
          \$ErrorActionPreference = 'Stop' ; \
          \$ProgressPreference = 'SilentlyContinue' ; \
          while(!(Test-Path -Path \$env:PSModuleAnalysisCachePath)) {  \
            Write-Host "'Waiting for $env:PSModuleAnalysisCachePath'" ; \
            Start-Sleep -Seconds 6 ; \
          }"

# Install PowerShell Modules
RUN pwsh -c "Install-Module SimplySql -force"
RUN pwsh -c "Install-Module -Name Pode -force"

# Copy files 
COPY ./data /data

# Start API on container start
CMD pwsh -f /data/Start-API.ps1