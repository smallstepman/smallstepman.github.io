{ inputs }: final: prev: {
  uniclip = final.buildGoModule {
    pname = "uniclip";
    version = "0-unstable";
    src = inputs.uniclip-src;
    vendorHash = "sha256-ugrWrB0YVs/oWAR3TC3bEpt1VXQC1c3oLrvFJxlR8pw=";
    patches = [ ./uniclip-bind-and-env-password.patch ];
    meta.description = "Universal clipboard - copy on one device, paste on another";
  };
}
