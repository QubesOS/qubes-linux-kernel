#!/usr/bin/python3

import sys
import argparse
import requests
import json

from packaging import version
from packaging.version import parse as parse_version


class KernelUpdaterClient:
    def __init__(self, version, branch):
        self.version = version
        self.branch = branch

    def get_version_qubes(self):
        return self.version

    def get_version_upstream(self):
        url_releases = 'https://www.kernel.org/releases.json'
        r = requests.get(url_releases)
        latest_upstream = None
        if 200 <= r.status_code < 300:
            content = json.loads(r.content.decode('utf-8'))
            releases = [rel['version'] for rel in content['releases'] if
                        rel['moniker'] in ('stable', 'longterm')]

            releases.sort(key=parse_version, reverse=True)

            if 'stable-' in self.branch:
                branch_version = self.branch.split('-')[1]
                releases = [rel for rel in releases if
                            rel.startswith(branch_version)]

            latest_upstream = releases[0]
        else:
            print('An error occurred while downloading "%s"' % url_releases)

        return latest_upstream

    def is_update_needed(self):
        version_qubes = self.get_version_qubes()
        version_upstream = self.get_version_upstream()
        if version_qubes and version_upstream and (version.parse(version_qubes) < version.parse(version_upstream)):
            return version_upstream

def parse_args(argv):
    parser = argparse.ArgumentParser()

    parser.add_argument('--check-update', required=False, action='store_true')
    parser.add_argument('--version', required=True)
    parser.add_argument('--branch', required=True)

    args = parser.parse_args(argv[1:])

    return args


def main(argv):
    args = parse_args(argv)
    client = KernelUpdaterClient(version=args.version, branch=args.branch)

    if args.check_update:
        is_update_needed = client.is_update_needed()
        if is_update_needed is not None:
            print(is_update_needed)

    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
