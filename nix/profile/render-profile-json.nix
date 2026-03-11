{
  aggregate ? import ./aggregate.nix { },
}:
builtins.toJSON aggregate + "\n"
