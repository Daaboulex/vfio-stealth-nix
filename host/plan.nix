{ lib, cfg }:

let
  pageKb = if cfg.hugepages.size == "1G" then 1048576 else 2048;

  log2 = n: if n <= 1 then 0 else 1 + log2 (n / 2);

  gpuFunctions =
    gpu: [ gpu.address ] ++ lib.optional (gpu.audio != null) gpu.audio ++ gpu.extraFunctions;
in
{
  inherit (cfg.host) protectedDisks;
  inherit (cfg.pinning) isolate;
  hugepages = {
    inherit pageKb;
    inherit (cfg.hugepages) atBoot;
  };
  domains = lib.mapAttrs (_: domain: {
    devices = lib.optionals (domain.gpu != null) (gpuFunctions domain.gpu) ++ domain.hostDevices;
    inherit (domain) unmount stopServices iommu;
    hugepages = if domain.hugepages then domain.memory * 1024 / pageKb else 0;
    gpu =
      if domain.gpu != null && domain.gpu.binding == "hook" then
        {
          functions = gpuFunctions domain.gpu;
          resizeBar2 = if domain.gpu.resizeBar2Mb != null then log2 domain.gpu.resizeBar2Mb else null;
          inherit (domain.gpu) rebindOnStop;
        }
      else
        null;
    vcpus = if domain.pinning != null then domain.pinning.vcpus else [ ];
  }) cfg.domains;
}
