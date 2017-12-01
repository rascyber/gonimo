{}:

(import ../reflex-platform {}).project ({ pkgs, ... }: {
  packages = {
    gonimo-common = ./common;
    gonimo-back = ./back;
    gonimo-front = ./front;
  };

  android.front = {
    executableName = "gonimo-front-android";
    applicationId = "org.gonimo.gonimo";
    displayName = "Gonimo";
    assets = ./front/static;
    intentFilters = ''
      <intent-filter>
          <action android:name="android.intent.action.VIEW"/>
          <category android:name="android.intent.category.DEFAULT"/>
          <data android:scheme="https" />
          <data android:host="app.alpha.gonimo.com" />
      </intent-filter>
    '';
    permissions = ''
      <uses-permission android:name="android.permission.CAMERA" />
      <uses-permission android:name="android.permission.RECORD_AUDIO" />
      <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
      <uses-feature android:name="android.hardware.camera.autofocus" />
    '';
  };

  overrides = self: super: {
    reflex-host = self.callPackage ./reflex-host.nix {};
    gonimo-deploy = self.callPackage ./gonimo-deploy.nix {};
  #       lens = self.callHackage "lens" "4.15.4" {};
  #       free = self.callCabal2nix "free" (pkgs.fetchFromGitHub {
  #         owner = "ekmett";
  #         repo = "free";
  #         rev = "a0c5bef18b9609377f20ac6a153a20b7b94578c9";
  #         sha256 = "0vh3hj5rj98d448l647jc6b6q1km4nd4k01s9rajgkc2igigfp6s";
  #       }) {};
  };

  tools = ghc : with ghc; [
    # ghc-mod
    gonimo-deploy
  ];

  shells = {
    ghc = ["gonimo-common" "gonimo-back" "gonimo-front"];
    ghcjs = ["gonimo-common" "gonimo-front"];
  };
})