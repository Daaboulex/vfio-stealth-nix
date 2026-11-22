{
  lib,
  pkgs,
  cfg,
  nixvirt,
  name,
  domain,
}:

let
  ids = lib.unique (
    lib.concatMap (device: [
      device.vendor
      device.product
    ]) domain.usb
  );
  hex = n: "0x${lib.fixedWidthString 4 "0" (lib.toLower (lib.toHexString n))}";
  tags = tag: map (n: "<${tag} id='${toString n}'/>") ids;
  hexTags = tag: map (n: "<${tag} id='${hex n}'/>") ids;
  iommu =
    if cfg.cpuVendor == "intel" then
      "<iommu model='intel'><driver intremap='on' caching_mode='on'/></iommu>"
    else
      "<iommu model='amd'><driver intremap='on'/></iommu>";
in
# why: NixVirt writes USB ids as decimal integers, and libvirt's schema takes at most four digits; it has no iommu element either
lib.replaceStrings (tags "vendor" ++ tags "product" ++ lib.optional domain.iommu "</devices>")
  (hexTags "vendor" ++ hexTags "product" ++ lib.optional domain.iommu "${iommu}</devices>")
  (
    nixvirt.lib.domain.getXML (
      import ./domain.nix {
        inherit
          lib
          pkgs
          cfg
          name
          domain
          ;
      }
    )
  )
