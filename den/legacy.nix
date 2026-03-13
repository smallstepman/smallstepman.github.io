{ den, ... }: {
  den.ctx.host.includes = [ (den.provides.import-tree._.host ./../machines) ];
  den.ctx.user.includes = [ (den.provides.import-tree._.user ./../users) ];
}
