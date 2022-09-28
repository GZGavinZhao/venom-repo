# Disclaimer

This repo is only for contributers/packagers so that they don't have to rebuild
everything to start contributing on top of Venom and all the binary packages do
not contain any proprietary software and are only for testing purposes only.

I will try my best to keep this repo in sync with
[upstream](https://github.com/snekpit/venom). Usually I'll do a sync every 24
hours. Feel free to ping me on Matrix if you want to sync a particular package.

# Instructions

Add this file: `/etc/boulder/profiles.conf.d/venom-x86_64.conf`
```yaml
- venom-x86_64:
    collections:
        - protosnek:
            uri: "https://dev.serpentos.com/protosnek/x86_64/stone.index"
            description: "Bootstrap repository"
            priority: 0
        - venom:
            uri: "https://venom-testing.oss-accelerate.aliyuncs.com/stone.index"
            descrpition: "Venom testing repository"
            priority: 10
```
Note: As you might be able to tell, the url is accelerated for worldwide
downloads,
which also means that any data that goes through this url will cost me a little
bit extra. If you happen to be in North America, you may consider using
`https://venom-testing.oss-us-east-1.aliyuncs.com/stone.index` to reduce a
little bit of
cost. No worries if you can't, because 100GB of accelerated data will only cost
me less than 10 dollars.

Now you can build against Venom through `sudo boulder build -p venom-x86_64`!

# For Maintainers

The `utils.sh` provides utility commands to automatically build, upload, and/or
delete packages. To fully utilize the commands, you need to have the following
programs available in your path:

- [`aliyun`](https://github.com/aliyun/aliyun-cli). If you're on Solus, you can
  download it from the [grocery
  store](https://gitlab.com/solus-grocery-store/solus-grocery-store).
- [`fd`](https://github.com/sharkdp/fd)

More documentation on the commands later...
