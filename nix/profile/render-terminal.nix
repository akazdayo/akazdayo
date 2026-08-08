{
  aggregate ? import ./aggregate.nix { },
  ansi ? false,
}:
let
  joinLines = lines: builtins.concatStringsSep "\n" lines;

  take =
    count: values:
    if count <= 0 || values == [ ] then
      [ ]
    else
      [ (builtins.head values) ] ++ take (count - 1) (builtins.tail values);

  repeat = count: value: builtins.concatStringsSep "" (builtins.genList (_: value) count);

  stripPrefix =
    prefix: value:
    let
      prefixLength = builtins.stringLength prefix;
      valueLength = builtins.stringLength value;
    in
    if builtins.substring 0 prefixLength value == prefix then
      builtins.substring prefixLength (valueLength - prefixLength) value
    else
      value;

  contactHref =
    label:
    let
      matches = builtins.filter (link: link.label == label) aggregate.contact.links;
    in
    if matches == [ ] then "-" else (builtins.head matches).href;

  namedLanguages = builtins.filter (entry: entry.language != null) aggregate.languageCounts;
  languageSummary = builtins.concatStringsSep ", " (map (entry: entry.language) (take 5 namedLanguages));

  escape = builtins.fromJSON ''"\u001b"'';
  reset = "${escape}[0m";
  boldBlue = "${escape}[1;38;5;75m";
  blue = "${escape}[38;5;75m";
  cyan = "${escape}[38;5;81m";
  paint = color: value: if ansi then "${color}${value}${reset}" else value;

  key = value: paint cyan value;
  title = paint boldBlue "${aggregate.identity.handle}@github";
  rule = paint blue (repeat (builtins.stringLength "${aggregate.identity.handle}@github") "-");

  xContact = stripPrefix "https://" (contactHref "X");
  emailContact = stripPrefix "mailto:" (contactHref "E-Mail");
  githubHost = stripPrefix "https://" aggregate.identity.github;

  colorBlocks =
    if ansi then
      "${escape}[40m   ${escape}[41m   ${escape}[42m   ${escape}[43m   ${escape}[44m   ${escape}[45m   ${escape}[46m   ${escape}[47m   ${reset}"
    else
      "■ ■ ■ ■ ■ ■ ■ ■";

  infoLines = [
    title
    rule
    "${key "Profile"}: ${aggregate.hero.heading.text}"
    "${key "Host"}: ${githubHost}"
    "${key "Repositories"}: ${toString aggregate.repoCount}"
    "${key "Stars"}: ${toString aggregate.totalStars}"
    "${key "Languages"}: ${languageSummary}"
    "${key "Nix Repositories"}: ${toString (builtins.length aggregate.nixRepos)}"
    "${key "X"}: ${xContact}"
    "${key "Email"}: ${emailContact}"
    "${key "Flake"}: ${aggregate.reproducible.flake}#profile"
    colorBlocks
  ];

in
joinLines infoLines + "\n"
