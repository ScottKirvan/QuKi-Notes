set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]

default:
    @just --list

android device='':
    flutter run {{ if device != '' { '--device-id ' + device } else { '' } }}
windows:
    flutter run -d windows

linux:
    flutter run -d linux

test:
    flutter test

lint:
    flutter analyze
    dart format --output=none --set-exit-if-changed lib/ test/

gen:
    dart run build_runner build --delete-conflicting-outputs
    dart run drift_dev schema dump lib/core/database/app_database.dart test/db/schemas/

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
