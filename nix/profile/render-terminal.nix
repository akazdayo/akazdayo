{
  aggregate ? import ./aggregate.nix { },
}:
let
  joinLines = lines: builtins.concatStringsSep "\n" lines;

  take =
    count: values:
    if count <= 0 || values == [ ] then
      [ ]
    else
      [ (builtins.head values) ] ++ take (count - 1) (builtins.tail values);

  renderLanguage = entry: "${if entry.language == null then "Other" else entry.language} (${toString entry.count})";
  namedLanguages = builtins.filter (entry: entry.language != null) aggregate.languageCounts;
  languageSummary = builtins.concatStringsSep ", " (map renderLanguage (take 5 namedLanguages));

  shownNixRepos = take 5 aggregate.nixRepos;
  hiddenNixRepoCount = builtins.length aggregate.nixRepos - builtins.length shownNixRepos;
  nixRepoSummary =
    builtins.concatStringsSep ", " (map (repo: repo.name) shownNixRepos)
    + (if hiddenNixRepoCount == 0 then "" else " + ${toString hiddenNixRepoCount} more");

  renderContact = link: "  ${link.label}: ${link.href}";
in
joinLines (
  [
    "${aggregate.hero.heading.emoji} ${aggregate.hero.heading.text}"
    ""
    "GitHub: ${aggregate.identity.github}"
    "Repositories: ${toString aggregate.repoCount}"
    "Stars: ${toString aggregate.totalStars}"
    "Languages: ${languageSummary}"
  ]
  ++ (if aggregate.nixRepos == [ ] then [ ] else [ "Nix repositories: ${nixRepoSummary}" ])
  ++ [
    ""
    "Contact"
  ]
  ++ map renderContact aggregate.contact.links
  ++ [
    ""
    "Evaluated from ${aggregate.reproducible.flake}#profile"
  ]
) + "\n"
