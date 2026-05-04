export function parseRoadmapFile(fileName, content) {
  const lines = content.split(/\r?\n/);
  const title = readTitle(lines, fileName);
  const status = readSectionText(lines, 'Status');
  const items = readChecklistItems(lines);

  if (items.length === 0) {
    return {
      ok: false,
      fileName,
      error: 'No roadmap checklist items found.'
    };
  }

  const completedCount = items.filter((item) => item.done).length;

  return {
    ok: true,
    fileName,
    roadmap: {
      fileName,
      title,
      status,
      completedCount,
      totalCount: items.length,
      items
    }
  };
}

export function summarizeRoadmaps(files) {
  const roadmaps = [];
  const errors = [];

  for (const file of files) {
    const result = parseRoadmapFile(file.name, file.content);

    if (result.ok) {
      roadmaps.push(result.roadmap);
    } else {
      errors.push(result);
    }
  }

  return {
    roadmaps,
    errors,
    emptyMessage: 'No roadmaps loaded.'
  };
}

function readTitle(lines, fallback) {
  const titleLine = lines.find((line) => line.startsWith('# '));
  return titleLine ? titleLine.replace(/^#\s+/, '').trim() : fallback;
}

function readSectionText(lines, sectionName) {
  const sectionIndex = lines.findIndex((line) =>
    line.trim().toLowerCase() === `## ${sectionName.toLowerCase()}`
  );

  if (sectionIndex === -1) {
    return 'Unknown';
  }

  for (const line of lines.slice(sectionIndex + 1)) {
    const trimmed = line.trim();

    if (trimmed.startsWith('## ')) {
      break;
    }

    if (trimmed.length > 0) {
      return trimmed;
    }
  }

  return 'Unknown';
}

function readChecklistItems(lines) {
  return lines.flatMap((line) => {
    const match = line.match(/^\s*(?:[-*]|\d+\.)\s+\[(x|X| )\]\s+(.+)$/);

    if (!match) {
      return [];
    }

    return [
      {
        done: match[1].toLowerCase() === 'x',
        text: match[2].trim()
      }
    ];
  });
}
