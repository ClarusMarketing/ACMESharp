## This was copied from a build session with custom build command disabled
##    msbuild "ACMESharp\ACMESharp.sln" /verbosity:minimal /logger:"C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll"

## This logic was adapted from:
##    http://arkfps.github.io/2015/01/07/using-coverity-scan-with-appveyor/

$msb_prog = "msbuild"
$msb_args = @(
    ,'ACMESharp\ACMESharp.sln'
	,'/verbosity:minimal'
    ,'/logger:C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll'
	
	## These can be set to target specific build target configuration
	#,'/p:Configuration=$env:CONFIGURATION'
	#,'/p:Platform=$env:PLATFORM'
)

$doCoverity = $false
try { $doCoverity = ((wget http://acmesharp.zyborg.io/appveyor-coverity.txt).Content -eq 1) }
catch { }
if ($doCoverity) {
    Write-Warning "Detected build with Coverity Scan request"
	& cov-build.exe --dir cov-int $msb_prog $msb_args
}
else {
    Write-Output "Running *normal* build"
    & $msb_prog $msb_args

    Write-Output "Building nuget packages"
	.\ACMESharp\ACMESharp\mynuget.cmd
	.\ACMESharp\ACMESharp.PKI.Providers.OpenSslLib32\mynuget.cmd
	.\ACMESharp\ACMESharp.PKI.Providers.OpenSslLib64\mynuget.cmd

	Write-Output "Building choco packages"
	.\ACMESharp\ACMESharp.POSH\choco\acmesharp-posh\choco-pack.cmd
	.\ACMESharp\ACMESharp.POSH-test\choco\acmesharp-posh-all\choco-pack.cmd

    Write-Output "Publishing POSH modules to staging repo:"
    Write-Output "  * Update and import the latest PSGet module"
    Install-Module -Name PowerShellGet -Force
    Import-Module PowerShellGet -Force
    Write-Output "  * Registering STAGING repo"
    Register-PSRepository -Name STAGING -PackageManagementProvider NuGet -InstallationPolicy Trusted `
            -SourceLocation https://int.nugettest.org/api/v2 `
            -PublishLocation https://int.nugettest.org/api/v2/package

    $modName = "ACMESharp.Providers.CloudFlare"
    ## First we need to publish the module which will force the packaging process of the PSGet module
    Write-Output "  * Publishing CloudFlare Provider module [$modName]"
    Publish-Module -Path ".\ACMESharp\$($modName)\bin\$($env:CONFIGURATION)\$($modName)" `
            -Repository STAGING -NuGetApiKey $env:STAGING_NUGET_APIKEY -Force -ErrorAction Stop
    ## Then we pull the module back down from the STAGING repo 
    #$modPkgWeb = Invoke-WebRequest -Uri "https://staging.nuget.org/api/v2/package/$($modName)" -MaximumRedirection 0 -ErrorAction Ignore
    #$modPkgUri = New-Object uri($modPkgWeb.Headers.Location)
    #$modPkg = $modPkgUri.Segments[-1]
    Invoke-WebRequest -Uri "https://staging.nuget.org/api/v2/package/$($modName)" `
            -OutFile ".\ACMESharp\$($modName)\bin\$($modName).$($env:APPVEYOR_BUILD_VERSION).nupkg"
}
