{
  static ? import ./static.nix,
  schema ? import ./schema.nix,
  repos ? if builtins.pathExists ../../repos.nix then import ../../repos.nix else [ ],
  selfRepoName ? "akazdayo",
}:
let
  machineRepos = schema.machineReadableRepos repos;
  featuredRepos = schema.featuredRepos machineRepos;
  recentlyUpdatedSource = schema.recentRepos machineRepos;

  listOptional = condition: value: if condition then [ value ] else [ ];

  byPushedAtDesc =
    left: right:
    if left.pushedAt != right.pushedAt then left.pushedAt > right.pushedAt else left.name < right.name;

  languageCountLessThan =
    left: right:
    if left.count != right.count then
      left.count > right.count
    else if left.language == null && right.language == null then
      false
    else if left.language == null then
      false
    else if right.language == null then
      true
    else
      left.language < right.language;

  topicCountLessThan =
    left: right:
    if left.count != right.count then left.count > right.count else left.topic < right.topic;

  incrementLanguageCount =
    counts: language:
    if builtins.any (entry: entry.language == language) counts then
      map (
        entry: if entry.language == language then entry // { count = entry.count + 1; } else entry
      ) counts
    else
      counts
      ++ [
        {
          inherit language;
          count = 1;
        }
      ];

  incrementTopicCount =
    counts: topic:
    if builtins.any (entry: entry.topic == topic) counts then
      map (entry: if entry.topic == topic then entry // { count = entry.count + 1; } else entry) counts
    else
      counts
      ++ [
        {
          inherit topic;
          count = 1;
        }
      ];

  languageCounts = builtins.sort languageCountLessThan (
    builtins.foldl' (counts: repo: incrementLanguageCount counts repo.language) [ ] machineRepos
  );

  topTopics = builtins.sort topicCountLessThan (
    builtins.foldl' (
      counts: repo: builtins.foldl' incrementTopicCount counts repo.topics
    ) [ ] machineRepos
  );

  totalStars = builtins.foldl' (sum: repo: sum + repo.stars) 0 machineRepos;

  recentlyUpdated = builtins.sort byPushedAtDesc recentlyUpdatedSource;

  nixRepos = builtins.filter (
    repo: repo.language == "Nix" || builtins.elem "nix" repo.topics
  ) machineRepos;

  selfRepoMatches = builtins.filter (repo: repo.name == selfRepoName) machineRepos;
  selfRepo = if selfRepoMatches == [ ] then null else builtins.head selfRepoMatches;

  footnoteLink = if static ? footnote && static.footnote ? link then static.footnote.link else null;
  repositoryLink =
    if selfRepo == null then
      null
    else
      {
        label = selfRepo.name;
        href = selfRepo.url;
      };
in
{
  inherit (schema) committedSnapshot normalization aggregation;
  inherit static;
  inherit (static)
    hero
    contact
    stats
    details
    readme
    footnote
    ;

  repoCount = builtins.length machineRepos;
  inherit totalStars;

  repos = machineRepos;
  inherit
    featuredRepos
    languageCounts
    topTopics
    recentlyUpdated
    nixRepos
    ;

  selfReference = {
    name = selfRepoName;
    included = selfRepo != null;
    repo = selfRepo;
    note = static.readme.sections.aboutThisReadme.selfReferenceNote;
  };

  links = {
    hero = static.hero.links;
    contact = static.contact.links;
    footnote = footnoteLink;
    repository = repositoryLink;
    all =
      static.hero.links
      ++ static.contact.links
      ++ listOptional (footnoteLink != null) footnoteLink
      ++ listOptional (repositoryLink != null) repositoryLink;
  };
}
