$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# Ensure pytest is available via the py launcher
py -m pytest --version *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "pytest not found - installing dev requirements..." -ForegroundColor Yellow
    py -m pip install -r "$PSScriptRoot\tests\requirements-dev.txt"
}

py -m pytest tests -v $args
