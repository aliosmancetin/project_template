(list (channel
        (name 'guix)
        (url "https://git.savannah.gnu.org/git/guix.git")
        (branch "master")
        (commit
          "fc29a7193781df44a15cb7a8bdc236805ddd0595")
        (introduction
          (make-channel-introduction
            "9edb3f66fd807b096b48283debdcddccfea34bad"
            (openpgp-fingerprint
              "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
      (channel
        (name 'guix-cran)
        (url "https://github.com/guix-science/guix-cran.git")
        (branch "master")
        (commit
          "71b6082841c88f49a65da494bec13f21c906b1c4"))
      (channel
        (name 'guix-bioc)
        (url "https://github.com/guix-science/guix-bioc.git")
        (branch "master")
        (commit
          "5a29eb6d3a4307393b1b4c0ceb842f80602e0309"))
      (channel
        (name 'guix-science)
        (url "https://codeberg.org/guix-science/guix-science.git")
        (branch "master")
        (commit
          "31387efc4d90362e79251953fd1a6554dc262cda")
        (introduction
          (make-channel-introduction
            "b1fe5aaff3ab48e798a4cce02f0212bc91f423dc"
            (openpgp-fingerprint
              "CA4F 8CF4 37D7 478F DA05  5FD4 4213 7701 1A37 8446")))))
