#!/usr/bin/env python3
"""Summarize logs produced by the documented diagnostic-only XLAT patch."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('logs', nargs='+', type=Path)
args = parser.parse_args()
reports = []
for path in args.logs:
    data = path.read_bytes()
    text = data.decode(errors='replace')
    allocations = [(int(a), int(b)) for a, b in re.findall(r'XLAT_ALLOC used=(\d+) max=(\d+)', text)]
    if not allocations:
        parser.error(f'{path}: no XLAT_ALLOC records; use the diagnostic patch')
    maximum = max(a for a, _ in allocations)
    limits = {b for _, b in allocations}
    if len(limits) != 1:
        parser.error(f'{path}: inconsistent limits')
    limit = limits.pop()
    before_normal = text.split('Primary CPU switching to normal world boot', 1)[0]
    boot_allocations = [int(a) for a in re.findall(r'XLAT_ALLOC used=(\d+)', before_normal)]
    events = collections.Counter(re.findall(r'XLAT_(COPY|SPLIT) level=(\d+)', text))
    reports.append({'log': path.name, 'sha256': hashlib.sha256(data).hexdigest(),
                    'max_tables': limit, 'peak_tables_used': maximum,
                    'unused_tables_at_observed_peak': limit-maximum,
                    'table_size_bytes': 4096, 'peak_table_bytes': maximum*4096,
                    'allocation_records': len(allocations),
                    'peak_before_normal_world': max(boot_allocations, default=None),
                    'events': {kind+'_level_'+level: count for (kind, level), count in sorted(events.items())},
                    'map_calls': len(re.findall(r'XLAT_MAP ', text)),
                    'panic': "Panic '" in text or 'xlat tables exhausted' in text})
print(json.dumps(reports, indent=2))
