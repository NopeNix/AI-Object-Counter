Import-Module Pode
Import-Module SimplySql

#  PREPARATION: Check if connection to DB Server is possible
Write-Host ("[Preparation] Trying to reach MariaDB Server '$env:MariaDBHost' on Port $env:MariaDBPort with user '$env:MariaDBUsername'...") -ForegroundColor Blue
try {
    Open-MySqlConnection -ConnectionName "Test" -CommandTimeout 5000 -Server $env:MariaDBHost -Port $env:MariaDBPort -Credential (New-Object System.Management.Automation.PSCredential ($env:MariaDBUsername, (ConvertTo-SecureString $env:MariaDBPassword -AsPlainText -Force))) -WarningAction SilentlyContinue -ErrorAction Stop
    Close-SqlConnection -ConnectionName "Test"
    Write-Host (" -> Connection possible!") -ForegroundColor Green
}
catch {
    Write-Host (" -> Connection cannot be etablished! " + $_.Exception.Message) -ForegroundColor Red
    Write-Host (" -> FATAL! The App needs a Database to function!") -ForegroundColor Red
    Throw ("FATAL! Connection to the MariaDB Server '$env:MariaDBHost' on Port $env:MariaDBPort with user '$env:MariaDBUsername' cannot be etablished! " + $_.Exception.Message + ". The App needs a Database to work as intended, cannot continue!")
    Exit 
}   
Write-Host ""

#  PREPARATION: Check if Database is already present
Write-Host ("[Preparation] Checking if Database '$env:MariaDBDatabase' is already present...") -ForegroundColor Blue
try {
    Open-MySqlConnection  -ConnectionName "Test" -CommandTimeout 5000 -Server $env:MariaDBHost -Port $env:MariaDBPort -Credential (New-Object System.Management.Automation.PSCredential ($env:MariaDBUsername, (ConvertTo-SecureString $env:MariaDBPassword -AsPlainText -Force))) -Database $env:MariaDBDatabase -WarningAction SilentlyContinue -ErrorAction Stop
    Close-SqlConnection -ConnectionName "Test"
    Write-Host (" -> Database is present!") -ForegroundColor Green
    $DBPresent = $true
}
catch {
    Write-Host (" -> Database is not present!") -ForegroundColor Yellow
    $DBPresent = $false
} 
Write-Host ""

#  PREPARATION: Create Database if not already present
if (!$DBPresent) {
    Write-Host ("[Preparation] Creating Database '$env:MariaDBDatabase'...") -ForegroundColor Blue
    try {
        Open-MySqlConnection -CommandTimeout 5000 -Server $env:MariaDBHost -Port $env:MariaDBPort -Credential (New-Object System.Management.Automation.PSCredential ($env:MariaDBUsername, (ConvertTo-SecureString $env:MariaDBPassword -AsPlainText -Force))) -WarningAction SilentlyContinue -ErrorAction Stop
        Invoke-SqlUpdate -Query ((Get-Content ($PSScriptRoot + "/sql/ai-people-counter.sql") -Raw).Replace("ai-people-counter", $env:MariaDBDatabase)) -ErrorAction Stop | Out-Null
        Write-Host (" -> Database has been created!") -ForegroundColor Green
    }
    catch {
        Write-Host (" -> Database cannot be created! " + $_.Exception.Message) -ForegroundColor Red
        Write-Host (" -> FATAL!") -ForegroundColor Red
        Throw ("FATAL! Database '$env:MariaDBDatabase' cannot be created! " + $_.Exception.Message + ". Cannot continue!")
        Exit 
    }
}
Write-Host ("")

# Start Pode Server
Write-Host ("[API Server] API Server is now Starting log output of it will follow here...") -ForegroundColor Blue
if ($env:OS -match "Windows") {
    $env:PodeExposureAddress = "localhost"
    Write-Host ("[API Server] OS: Windows ($env:OS)") 
}
else {
    $env:PodeExposureAddress = "*"
    Write-Host ("[API Server] OS: Linux ($env:OS)") 
}
Start-PodeServer {
    Add-PodeEndpoint -Address $env:PodeExposureAddress -Port 8081 -Protocol Http

    #Initialize OpenApi
    Enable-PodeOpenApi -Path '/docs/openapi' -Title 'Swagger API Documentation' -Description "" -RouteFilter '/api/*' -Version 0.420.69

    # Ensable Swagger
    Enable-PodeOpenApiViewer -Type Swagger -Path '/swagger' -OpenApiUrl '/docs/openapi' -DarkMode
    
    # Landing Page
    Add-PodeRoute -Method Get, Post -Path '/' -ScriptBlock {
        try {

            # Load Functions
            . ($PSScriptRoot + "/functions.ps1")

            # Perform Post Action
            $PostActionToast = ""
            if ($webevent.Method -ieq "post") {
                if ($null -eq $webevent.data.keeppics) {$KeepPics = 0} else {$KeepPics = 1}
                switch ($webevent.data.action) {
                    "add" { 
                        try {
                            Set-ScheduledCountJob -JobName $webevent.data.jobname -Model $webevent.data.model -Object $webevent.data.object -X $webevent.data.x -Y $webevent.data.y -Height $webevent.data.height -Width $webevent.data.width -FrequencyMinutes $webevent.data.frequency -URL $webevent.data.url -KeepPics $KeepPics
                            $PostActionToast += Get-ToastHTML -ToastHeader '<i style="color: #46a832" class="bi bi-check-square"></i> Success' -ToastIcon '' -ToastBody ("Job <b>" + $webevent.data.jobname + "</b> has been created!")
                        }
                        catch {
                            $PostActionToast += Get-ToastHTML -ToastHeader '<i style="color: #8a242e" class="bi bi-x-square"></i> Failed!' -ToastIcon '' -ToastBody ("Job <b>" + $webevent.data.jobname + "</b> could not be created! " + $_.Exception.Message)
                        }
                    }
                    "delete" { 
                        $RemoveResult = Remove-ScheduledCountJob -Id $webevent.data.id
                        if ($RemoveResult -ne "0") {
                            $PostActionToast += Get-ToastHTML -ToastHeader '<i style="color: #46a832" class="bi bi-check-square"></i> Success' -ToastIcon '' -ToastBody ("Job <b>" + $webevent.data.id + "</b> has been removed!")
                        }
                        else {
                            $PostActionToast += Get-ToastHTML -ToastHeader '<i style="color: #8a242e" class="bi bi-x-square"></i> Failed!' -ToastIcon '' -ToastBody ("Job <b>" + $webevent.data.id + "</b> could not be removed!")
                        }
                    }
                    "changestate" { 
                        $CurrectState = (Get-ScheduledCountJob | Where-Object { $_.id -eq $webevent.data.id }).enabled
                        if ($CurrectState -eq $false) {
                            Set-ScheduledCountJob -ID $webevent.data.id -Enable
                            $PostActionToast += Get-ToastHTML -ToastHeader '<i style="color: #46a832" class="bi bi-play">  Enabled</i> ' -ToastIcon '' -ToastBody ("Job <b>" + $webevent.data.id + "</b> has been Enabled! The System will now start collecting Data in the set Frequency.")
                        }
                        else {
                            Set-ScheduledCountJob -ID $webevent.data.id -Disable
                            $PostActionToast += Get-ToastHTML -ToastHeader '<i style="color: #46a832" class="bi bi-pause">  Disabled</i> ' -ToastIcon '' -ToastBody ("Job <b>" + $webevent.data.id + "</b> has been Disabled! Data will not be collected automatically")
                        }
                    }
                    Default {}
                }
            }


            # Load and fill HTML Template
            $HTML = Get-Content ($PSScriptRoot + "/html/template_landing.html") -raw
            $HTML = $HTML.Replace("///NAVBAR", (Get-NavMenuHTML -ActiveItem "scheduled-counts"))
            $HTML = $HTML.Replace("///OPTIONSAvailableAiModels", (Get-AvailableAiModels -OutputAsHTMLOptions))
            $HTML = $HTML.Replace("///POSTTOAST", ($PostActionToast -join ""))
            $HTML = $HTML.Replace("///SCHEDULEDCOUNTJOB", (Get-ScheduledCountJob -AsHTMLTable))
            Set-PodeSecurityAccessControl -Origin '*' -Methods '*' -Headers '*' -Duration 7200    
            Write-PodeHtmlResponse $HTML


        }
        catch {
            Write-PodeTextResponse ("Ërror: ", $_.Exception.Message)
        }
    }

    # Test Page
    Add-PodeRoute -Method Get, Post -Path '/test' -ScriptBlock {
        # Load Functions
        . ($PSScriptRoot + "/functions.ps1")

        # Load and fill HTML Template
        $HTML = Get-Content ($PSScriptRoot + "/html/template_test.html") -raw
        $HTML = $HTML.Replace("///NAVBAR", (Get-NavMenuHTML -ActiveItem "test"))
        $HTML = $HTML.Replace("///AIMODELSCARDS", (Get-AvailableAiModels -OutputAsHTMLCards))
        $HTML = $HTML.Replace("///OPTIONSAvailableAiModels", (Get-AvailableAiModels -OutputAsHTMLOptions))
        Write-PodeHtmlResponse $HTML
    }

    # Info Page
    Add-PodeRoute -Method Get, Post -Path '/info' -ScriptBlock {
        # Load Functions
        . ($PSScriptRoot + "/functions.ps1")

        # Load and fill HTML Template
        $HTML = Get-Content ($PSScriptRoot + "/html/template_info.html") -raw
        $HTML = $HTML.Replace("///NAVBAR", (Get-NavMenuHTML -ActiveItem "info"))
        $HTML = $HTML.Replace("///AIMODELSCARDS", (Get-AvailableAiModels -OutputAsHTMLCards))
        $HTML = $HTML.Replace("///GPUINFO", (Get-GPUInfo -AsHTMLTable).Replace('<table>', '<table class="table table-striped">'))
        if ($webevent.Method -ieq "post") {
            $HTML = $HTML.Replace("///POSTVARIABLES", ("<h2>Post Variables</h2>" + ($webevent.data | ConvertTo-Html -Fragment).Replace('<table>', '<table class="table">') + "</pre>"))
        }
        else {
            $HTML = $HTML.Replace("///POSTVARIABLES", "")
        }
        Write-PodeHtmlResponse $HTML
    }

    # Swagger Page
    Add-PodeRoute -Method Get -Path '/swagger-api' -ScriptBlock {
        # Load Functions
        . ($PSScriptRoot + "/functions.ps1")

        # Load and fill HTML Template
        $HTML = Get-Content ($PSScriptRoot + "/html/template_swagger.html") -raw
        $HTML = $HTML.Replace("///NAVBAR", (Get-NavMenuHTML -ActiveItem "swagger"))

        Write-PodeHtmlResponse $HTML
    }

    # API : Get-AvailableAiModels
    Add-PodeRoute -Method Get -Path "/api/Get-AvailableAiModels" -ScriptBlock {
        # Load Functions
        . ($PSScriptRoot + "/functions.ps1")

        Get-AvailableAiModels | ConvertTo-Json | Write-PodeJsonResponse
    } -PassThru | Set-PodeOARouteInfo -Summary 'Get availalbe AIs for processing Images' -Tag "General"

    # API : Analyze-URL
    New-PodeOAStringProperty -Name 'URL' -Description "URL to image which should be analyized by the AI, e.g. https://webcams.com/queue_entrance2.jpeg" -Required | ConvertTo-PodeOAParameter -In Query | Add-PodeOAComponentParameter -Name 'Set2' 
    Add-PodeRoute -Method Post -Path "/api/Analyze-URL" -ScriptBlock {
        try {
            # Load Functions
            . ($PSScriptRoot + "/functions.ps1")

            if ($null -ne $webevent.data.URL -and $webevent.data.URL -ne "") {
                $AIResult = Get-AIAnalysis -URL $webevent.data.URL -Model $webevent.data.model -RawOutput $webevent.data.rawoutput -IncludePic $webevent.data.includepic -Filter $webevent.data.filter -MinConfidence $webevent.data.minconfidence

                if ($webevent.data.rawoutput) {
                    Write-PodeTextResponse ("<pre>" + ($AIResult | ConvertTo-Json )+ "</pre>")
                }
                else {
                    if ($AIResult.objects.count -gt 0) {
                        $Response = ($AIResult.objects | Select-Object Label, Score | ConvertTo-Html -Fragment).Replace('<table>', "<table class='table'>")
                    }
                    else {
                        $Response = "<b>No matches with provided Filter<b>"
                    }

                    if ($webevent.data.includepic) {
                        $PicData = ('<div class="col-8">
                                       <img data-bs-toggle="modal" data-bs-target="#PicturePreviewModel" class="img-fluid" src="data:image/jpeg;base64,' + ($AIResult."image-base64-encoded" | Out-String) + '" alt="Base64 Image" />
                                        </div>
                                        
                                        <!-- Modal -->
                                        <div class="modal fade" id="PicturePreviewModel" tabindex="-1" aria-labelledby="PicturePreviewModelLabel" aria-hidden="true">
                                        <div class="modal-dialog modal-xl">
                                            <div class="modal-content">
                                            <div class="modal-body">
                                                <img data-bs-toggle="modal" data-bs-target="#PicturePreviewModel" class="img-fluid" src="data:image/jpeg;base64,' + ($AIResult."image-base64-encoded") + '" alt="Base64 Image" />
                                            </div>
                                            </div>
                                        </div>
                                        </div>
                                        
                                        ')
                    }
                    $Response = ('<div class="container text-center">
                                    <div class="row">
                                        ' + $PicData + '
                                        <div class="col">
                                            ' + $Response + '
                                        </div>
                                    </div>
                                    </div>')
                    
                    Write-PodeTextResponse ($Response)
                }
            }
            else {
                Write-PodeJsonResponse ((('{ "Error":  "Parameter URL is missing in Body" }') | ConvertTo-Json))
            }
        }
        catch {
            Write-PodeJsonResponse @{
                "Fatal Error" = $_.Exception.Message 
                "Error Details" = $_.PSMessageDetails
                "MyCommand.Name" = $_.InvocationInfo.MyCommand.Name
                "ErrorDetails.Message" = $_.ErrorDetails.Message
                "InvocationInfo.PositionMessage" = $_.InvocationInfo.PositionMessage
                "CategoryInfo" = $_.CategoryInfo.ToString()
                "FullyQualifiedErrorId" = $_.FullyQualifiedErrorId
            }
        }
    } -PassThru | Set-PodeOARouteInfo -Summary 'Analyze URL' -Tag "General" -PassThru | Set-PodeOARequest -Parameters @(ConvertTo-PodeOAParameter -Reference 'Set2' )

    # API : Get-ScheduledCountJob
    Add-PodeRoute -Method Get -Path "/api/Get-ScheduledCountJob" -ScriptBlock {
        # Load Functions
        . ($PSScriptRoot + "/functions.ps1")

        Get-ScheduledCountJob | Select-Object id, jobname, object, frequencymin, URL, enabled, created, lastchanged  | ConvertTo-Json | Write-PodeJsonResponse   
    } -PassThru | Set-PodeOARouteInfo -Summary 'Get All Scheduled Count Jobs' -Tag "Job Management"

    # API : Set-ScheduledCountJob
    New-PodeOAStringProperty -Name 'Jobname' -Description "Will also be used as MariaDB Datatablename (all lowercase + spaces are `"-`") no special chars allowed! e.g. Queue Entrance 2" -Required | ConvertTo-PodeOAParameter -In Query | Add-PodeOAComponentParameter -Name 'Set' 
    New-PodeOAStringProperty -Name 'Object' -Description "Name of the Object which should be counted, e.g. Person" -Required | ConvertTo-PodeOAParameter -In Query | Add-PodeOAComponentParameter -Name 'Set'
    New-PodeOAIntProperty  -Name 'Frequency' -Description "Frequency how often the AI Should analyize the given image in Minutes. e.g. 5" -Required | ConvertTo-PodeOAParameter -In Query | Add-PodeOAComponentParameter -Name 'Set'
    New-PodeOAStringProperty -Name 'URL' -Description "URL to image which should be analyized by the AI, e.g. https://webcams.com/queue_entrance2.jpeg" -Required | ConvertTo-PodeOAParameter -In Query | Add-PodeOAComponentParameter -Name 'Set'
    New-PodeOAStringProperty -Name 'Model' -Description "Choose which AI Model should anaylze your Picture" -Required | ConvertTo-PodeOAParameter -In Query | Add-PodeOAComponentParameter -Name 'Set'
    Add-PodeRoute -Method Post -Path "/api/Set-ScheduledCountJob" -ScriptBlock {
        # Load Functions
        . ($PSScriptRoot + "/functions.ps1")

        Get-ScheduledCountJob | Select-Object id, jobname, object, frequencymin, URL, enabled, created, lastchanged  | ConvertTo-Json | Write-PodeJsonResponse   
    } -PassThru | Set-PodeOARouteInfo -Summary 'Change or Set a Count Job' -Tag "Job Management" -PassThru | Set-PodeOARequest -Parameters @(ConvertTo-PodeOAParameter -Reference 'Set' )
    
    # API : Remove-ScheduledCountJob
    New-PodeOAStringProperty -Name 'ID' -Description "ID of Record to remove" -Required | ConvertTo-PodeOAParameter -In Query | Add-PodeOAComponentParameter -Name 'Remove'
    Add-PodeRoute -Method Delete -Path "/api/Remove-ScheduledCountJob" -ScriptBlock {
        # Load Functions
        . ($PSScriptRoot + "/functions.ps1")

        Remove-ScheduledCountJob -Id $webevent.data.id  
    } -PassThru | Set-PodeOARouteInfo -Summary 'Change or Set a Count Job' -Tag "Job Management" -PassThru | Set-PodeOARequest -Parameters @(ConvertTo-PodeOAParameter -Reference 'Remove' )



} -Verbose -Debug -Threads 5