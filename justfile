set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]

default:
    @just --list

# Wire the committed pre-commit hook — run once after cloning.
setup:
    git config core.hooksPath .githooks
    @echo "pre-commit hook active"

android:
    #!powershell.exe -NoLogo
    $devices = flutter devices --machine 2>$null | ConvertFrom-Json
    $phone = $devices | Where-Object { $_.targetPlatform -match 'android' -and $_.id -notmatch 'emulator' } | Select-Object -First 1 -ExpandProperty id
    $emu   = $devices | Where-Object { $_.id -match 'emulator' } | Select-Object -First 1 -ExpandProperty id
    if ($phone) {
        Write-Host "Using phone: $phone"
        flutter run --device-id $phone
    } elseif ($emu) {
        Write-Host "Using emulator: $emu"
        flutter run --device-id $emu
    } else {
        Write-Error "No Android device or emulator found."
        exit 1
    }

windows:
    flutter run -d windows

linux:
    flutter run -d linux

android-release:
    flutter run --release -d android

windows-release:
    flutter run --release -d windows

linux-release:
    flutter run --release -d linux

test:
    flutter test

lint:
    flutter analyze
    dart format --output=none --set-exit-if-changed lib/ test/

gen:
    dart run build_runner build --delete-conflicting-outputs

build-android-debug:
    flutter build apk --debug

build-android-release:
    flutter build apk --release

build-windows:
    flutter build windows --release

build-linux:
    flutter build linux --release

docs:
    cd docs && npm run dev
