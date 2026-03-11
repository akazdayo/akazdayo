{
  hero = {
    image = {
      alt = "banner";
      src = "img/hello_world.png";
    };

    heading = {
      level = 1;
      emoji = "👋";
      text = "Hi I'm akaz.";
    };

    links = [
      {
        kind = "badge";
        label = "X";
        alt = "https://twitter.com/akazdayo";
        image = "https://img.shields.io/twitter/follow/akazdayo?style=social";
        href = "https://twitter.com/akazdayo";
      }
      {
        kind = "badge";
        label = "nostr";
        alt = "nostr";
        image = "https://nostr-embed.odango.app/nprofile1qyxhwumn8ghj77tpvf6jumt9qy28wumn8ghj7un9d3shjtnyv9kh2uewd9hsqgqmam8w2hmfa0pgjpqrvphj3d0gawaty0fzvucwz26t7a3d98fpvgwg2wlq";
        href = "https://nostter.app/odango.app";
      }
    ];

    footnoteRefs = [ "1" ];
  };

  contact = {
    heading = "📮 Contact me";

    links = [
      {
        label = "X";
        href = "https://twitter.com/akazdayo";
      }
      {
        label = "E-Mail";
        href = "mailto:me@odango.app";
      }
    ];
  };

  stats = {
    heading = "📈 Stats";

    cards = [
      {
        label = "Graph";
        image = "https://github-profile-summary-cards.vercel.app/api/cards/profile-details?username=akazdayo&theme=zenburn";
      }
      {
        label = "lang";
        image = "https://github-profile-summary-cards.vercel.app/api/cards/repos-per-language?username=akazdayo&theme=zenburn&exclude=";
      }
    ];
  };

  details = [
    {
      summary = "osu!";

      cards = [
        {
          label = "osu";
          image = "https://osu-sig.vercel.app/card?user=akazdayo&mode=std&lang=en&round_avatar=true&animation=true&mini=true&w=667&h=200";
        }
      ];
    }
  ];

  readme = {
    sectionOrder = [
      "shortExplanation"
      "featuredRepositories"
      "languageTrends"
      "topicTrends"
      "recentActiveProjects"
      "aboutThisReadme"
      "links"
    ];

    sections = {
      shortExplanation = {
        heading = "Short Explanation";
        intro = [
          "This profile README is generated from the shared Nix aggregate, which combines the hand-maintained profile contract with the normalized repository snapshot."
          "It stays presentation-focused, deterministic, and aware that this generator repository is part of the observed input state, so it can appear in derived sections when present in `repos.nix`."
        ];
      };

      featuredRepositories = {
        heading = "Featured Repositories";
        empty = "No featured repositories are available in the aggregate yet.";
      };

      languageTrends = {
        heading = "Language Trends";
        empty = "No language data is available in the aggregate yet.";
      };

      topicTrends = {
        heading = "Topic Trends";
        empty = "No topic data is available in the aggregate yet.";
      };

      recentActiveProjects = {
        heading = "Recent Active Projects";
        empty = "No recent active projects are available in the aggregate yet.";
      };

      aboutThisReadme = {
        heading = "About This README";
        selfReferenceNote = "This repository is part of the observed input state and may appear in derived aggregates when present in repos.nix.";
        selfReferenceIncluded = "The generator repository is currently included in the observed state as";
        selfReferenceMissing = "The generator repository is tracked as part of the observed state contract and will appear in derived sections whenever it is present in `repos.nix`.";
        aggregateOwnership = "Static identity, contact destinations, summary cards, retained detail blocks, and the footnote stay declarative in `nix/profile/static.nix`, while repository-derived lists come from `nix/profile/aggregate.nix`.";
      };

      links = {
        heading = "Links";
        heroLabel = "Hero";
        contactLabel = "Contact";
        repositoryLabel = "Repository";
        footnoteLabel = "Footnote";
      };
    };
  };

  footnote = {
    id = "1";
    text = "You want this? You can get ";
    link = {
      label = "here";
      href = "https://github.com/akazdayo/nost-profile2?tab=readme-ov-file";
    };
    suffix = "!";
  };
}
