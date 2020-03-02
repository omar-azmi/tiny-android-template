# Tiny Android Template

*For Android projects written in Kotlin and/or Java, using the latest AndroidX libraries*

Requirements:
- Java Development Kit (JDK)
- *optional* Kotlin Compiler
- Android SDK
- 7-Zip
- Bash & Perl (Cygwin/MSYS if on Windows)

Does Not Require:
- Android Studio
- Gradle
- Apache Maven / Ant
- Any external build system

## Project Contents

- `res/layout/activity_main.xml`
	- UI mark-up
- `res/values/strings.xml`
	- Externalised strings
- `src/MainActivity.kt` OR `src-java/MainActivity.java`
	- The actual program
- `AndroidManifest.xml`
	- Header for the app

## Scripts

In chronological order:

- `kotlin-pre.sh`
	- Prepares a copy of the Kotlin standard library in DEX form
- `get-packages.sh`
	- Retrieves library packages from Google's Maven repository. Targets AndroidX artifacts.
- `export-libs.pl`
	- Combines and compiles library resources while resolving resource name merge conflicts
- `link.pl`
	- Links all resources, fixes library resource references, compiles library classes into DEX bytecode
- `make.sh`
	- Compiles the main project and combines it with the compiled libraries
- `run.sh`
	- Installs and runs the app on an Android phone using ADB
- `logs.sh`
	- Retrieves ADB logcat logs

## Getting the Android SDK

At the time of writing, https://dl.google.com/android/repository/repository2-1.xml contains a map of internal package links that form the Android SDK.
As far as I know, the only required SDK packages for compilation are `build-tools_<version>-<os>.zip` and `platform_<version>.zip`.
For running the app remotely, you'll find ADB inside `platform-tools_<version>-<os>.zip`.
To download the SDK packages, append the name of the zip archive to https://dl.google.com/android/repository/
(you'll find the package file names within the `<url>` tags of that repository.xml file)

## Usage

1) Prepare the Kotlin standard library *Only necessary for Kotlin projects*
- `./kotlin-pre.sh`

2) Get library packages
- `./get-packages.sh pkg-list.txt`

3) Unpack & merge libraries
- `./export-libs.pl`

4) Build libraries
- `./link.pl`

5) Create APK (you will need a KeyStore file for this. See "Notes" for details.)
- `./make.sh`

6) Install and run the app on a real device using ADB
- `./run.sh`

If your list of libraries change, go to step 3.

If you create or delete (or possibly rename) any resources, go to step 4.

Otherwise, simply running make.sh should be enough to ensure that you have a fresh build.

The `make.sh` script will compile anything that's in the `src` folder.
To compile the Java version, simply rename the `src` folder to something else and rename `src-java` to `src`.

## Notes

As long as your JDK version can target Java 8, this should work. Tested with OpenJDK 13.0.2.

You will need to make sure the "bin" directories for the JDK and for 7-Zip (and the Kotlin compiler if you're using Kotlin) are in the $PATH variable.

You may need to change some configuration variables found at the top of each script. `kotlin-pre.sh` in particular relies on a hard-coded path which is system dependent.

In order to build the APK, `apksigner` needs a KeyStore file. This can be generated with `keytool`, which comes with the JDK.

These scripts use the `d8` tool from the Android SDK (as opposed to `dx`). Thus, your build-tools version must be >= 28.0.1.

This template is based off https://github.com/authmane512/android-project-template
