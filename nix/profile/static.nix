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

    badges = [
      {
        kind = "image";
        label = "views";
        alt = "views";
        image = "https://komarev.com/ghpvc/?username=akazdayo&color=lightgray";
      }
      {
        kind = "image";
        label = "star";
        alt = "star";
        image = "https://img.shields.io/github/stars/akazdayo?style=social";
      }
    ];

    links = [
      {
        kind = "badge";
        label = "X";
        alt = "https://twitter.com/akazdango";
        image = "https://img.shields.io/twitter/follow/akazdango?style=social";
        href = "https://twitter.com/akazdango";
        suffix = "  ";
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
        href = "https://twitter.com/akazdango";
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
      "featuredRepositories"
      "languageTrends"
      "topicTrends"
      "recentActiveProjects"
      "links"
    ];

    sections = {
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
