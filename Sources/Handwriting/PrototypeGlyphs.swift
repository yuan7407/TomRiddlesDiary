//
//  PrototypeGlyphs.swift
//  模块：Handwriting（纯逻辑，只依赖 Foundation）
//
//  文件职责：汉字以外的字形——拉丁字母、数字、西文与中文标点——的笔顺中线（计划 P3）。
//
//  数据从哪来：**原样**搬自网页原型第二版（artifact `17m7Vat37j45NLc8NX7Sab`）页面里的 `MINI`
//  数据中以 `!` 开头的 99 行。原型说明：「英文字母和数字是 Hershey 单线字体，标点是我画的」。
//  Hershey 字体是 1967 年美国国家标准局发布的公有领域矢量字体。
//  用户拍板「规则冲突以原型为准」（决策 80），所以这里取代了 2026-08-29 手写定义的那套
//  （PenMove 词汇写的 27 个标点 + 62 个字母数字，E1c/E1d）：同一个标点不许有两份形状。
//  汉字不在这里：汉字用的是 makemeahanzi 的中线，和原型是同一份数据（`GlyphStrokeProvider`）。
//
//  为什么换：原型的中文标点是**半宽**的（逗号 0.52、句号 0.56 个字宽），原先那套全角标点
//  占满一整格，句读后面空出一大块（2026-11-17 用户截图里「一遍，」后面那段空就是它）。
//
//  编码（原型 `ingest` / `dec`）：一行 = `!十六进制码位!字宽(千分之一字高)!笔画…`，
//  笔画之间用空格隔开，每个坐标是一个字符：码值减 35（越过 92 号的反斜杠再减 1）
//  得到 0…90 的档位，映射到 −0.06…1.06。y 向下，与 makemeahanzi 一致。
//

import Foundation

nonisolated enum PrototypeGlyphs {
    /// 一个字形：字宽（以字高为 1）+ 笔画中线（归一化坐标，y 向下）。
    struct Glyph: Equatable, Sendable {
        let advanceWidth: Double
        let strokes: [[Point2D]]
    }

    /// 查一个字。没有返回 nil，由调用方决定怎么报「缺字」。
    static func glyph(for character: Character) -> Glyph? {
        table[character]
    }

    /// 解码表，第一次用到时建一次。
    private static let table: [Character: Glyph] = {
        var result: [Character: Glyph] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "!", omittingEmptySubsequences: false)
            // 行首是 `!`，所以第 0 段是空串：["", 码位, 字宽, 笔画]
            guard parts.count >= 3,
                  let code = UInt32(parts[1], radix: 16),
                  let scalar = Unicode.Scalar(code),
                  let advance = Double(parts[2])
            else { continue }
            let strokeText = parts.count > 3 ? parts[3] : ""
            let strokes: [[Point2D]] = strokeText.split(separator: " ").map { stroke in
                let values = stroke.unicodeScalars.map { decode($0) }
                return stride(from: 0, to: values.count - 1, by: 2).map { Point2D(x: values[$0], y: values[$0 + 1]) }
            }
            result[Character(scalar)] = Glyph(advanceWidth: advance / 1000, strokes: strokes)
        }
        // 全角空格：原型里没有，按「一个汉字宽、没有墨」补上（原先的手写定义也是这样）。
        result["\u{3000}"] = Glyph(advanceWidth: 1, strokes: [])
        return result
    }()

    /// 原型 `dec`：一个字符 → 一个坐标。90 档量化、−0.06…1.06 是原型编码的定义，不是经验值。
    static func decode(_ scalar: Unicode.Scalar) -> Double {
        var k = Double(scalar.value)
        if k > 92 { k -= 1 }
        return ((k - 35) / 90 * 1120 - 60) / 1000
    }

    /// 原型 `MINI` 里以 `!` 开头的 99 行，逐字未改。
    private static let raw = ##"""
!21!294!4<4[ 4f1i4k6i4f
!22!456!1<1K C<CK
!23!618!A31z N3>z 1PPP /^N^
!25!672!V</k :<>@>E<I8K4K/G/C1>6<:<>>E@L@R>V< N[I^GbGfLkPkTiVdV`R[N[
!26!726![P[NYKVKTNRRN^IdEiAk8k4i1f/b/^1X4VCNEKGGGCE>A<<>:C:G<NATLdPiTkYk[i[f
!27!294!4@1>4<6>6C4G1I
!28!402!A3<88>4G1R1[4f8o<vAz
!29!402!/3488><G>R>[<f8o4v/z
!2a!456!:I:d /PE^ EP/^
!2b!726!ECEk 1VYV
!2c!240!4b1d/b1`4b4f/k
!2d!726!1VYV
!2e!240!1`/b1d4b1`
!2f!618!T3-z
!30!564!<<6>1E/P/V1b6i<kAkGiLbNVNPLEG>A<<<
!31!564!6E:CA<Ak
!32!564!1G1E4@6>:<C<G>I@LELIINET/kNk
!33!564!4<L<>NENIPLRNXN^LdGiAk:k4i1f/b
!34!564!E</[P[ E<Ek
!35!564!I<4<1P4N:KAKGNLRNXN^LdGiAk:k4i1f/b
!36!564!LCI>C<><8>4E1P1[4d8i>kAkGiLdN^N[LTGPAN>N8P4T1[
!37!564!N<8k /<N<
!38!564!:<4>1C1G4K8NAPGRLVN[NbLfIiCk:k4i1f/b/[1V6R<PENIKLGLCI>C<:<
!39!564!LKIREV>X<X6V1R/K/I1C6><<><E>ICLKLVIbEi>k:k4i1d
!3a!240!1P/R1T4R1P 1`/b1d4b1`
!3b!240!1P/R1T4R1P 4b1d/b1`4b4f/k
!3d!726!1PYP 1^Y^
!3f!510!/G/E1@4>8<A<E>G@IEIIGNEP<T<[ <f:i<k>i<f
!40!780!PNNIIGCG>I<K:R:X<^A`G`L^NX CG>K<R<X>^A` PGNXN^R`V`[[^T^P[IYET@P>I<C<<>8@4E1I/P/V1^4b8f<iCkIkPiTfVd RGPXP^R`
!41!510!<<+k <<Nk 1[G[
!42!564!1<1k 1<E<L>N@PEPINNLPER 1RERLTNVP[PbNfLiEk1k
!43!618!PGNCI>E<<<8>4C1G/N/X1`4d8i<kEkIiNdP`
!44!564!1<1k 1<A<G>LCNGPNPXN`LdGiAk1k
!45!510!1<1k 1<N< 1RCR 1kNk
!46!456!1<1k 1<N< 1RCR
!47!618!PGNCI>E<<<8>4C1G/N/X1`4d8i<kEkIiNdP`PX EXPX
!48!618!1<1k P<Pk 1RPR
!49!240!1<1k
!4a!456!C<C`Af>i:k6k1i/f-`-[
!4b!564!1<1k P<1[ <PPk
!4c!402!1<1k 1kLk
!4d!672!1<1k 1<Ck T<Ck T<Tk
!4e!618!1<1k 1<Pk P<Pk
!4f!618!<<8>4C1G/N/X1`4d8i<kEkIiNdP`RXRNPGNCI>E<<<
!50!564!1<1k 1<E<L>N@PEPKNPLRET1T
!51!618!<<8>4C1G/N/X1`4d8i<kEkIiNdP`RXRNPGNCI>E<<< CbPo
!52!564!1<1k 1<E<L>N@PEPINNLPER1R ARPk
!53!564!NCI>C<:<4>/C/G1K4N8PETIVLXN^NdIiCk:k4i/d
!54!456!:<:k +<I<
!55!618!1<1^4d8i>kCkIiNdP^P<
!56!510!+<<k N<<k
!57!672!-<8k C<8k C<Nk Y<Nk
!58!564!/<Nk N</k
!59!510!+<<R<k N<<R
!5a!564!N</k /<N< /kNk
!61!564!IKIk IRENAK:K6N1R/X/^1d6i:kAkEiId
!62!510!1<1k 1R6N:KAKENIRLXL^IdEiAk:k6i1d
!63!510!IRENAK:K6N1R/X/^1d6i:kAkEiId
!64!564!I<Ik IRENAK:K6N1R/X/^1d6i:kAkEiId
!65!510!/XIXITGPENAK:K6N1R/X/^1d6i:kAkEiId
!66!402!><:<6>4E4k -K<K
!67!564!IKIoGvExAz:z6x IRENAK:K6N1R/X/^1d6i:kAkEiId
!68!564!1<1k 1T8N<KCKGNITIk
!69!240!/<1>4<1:/< 1K1k
!6a!294!4<6>8<6:4< 6K6q4x/z+z
!6b!456!1<1k GK1b :XIk
!6c!240!1<1k
!6d!834!1K1k 1T8N<KCKGNITIk ITPNTK[K`NbTbk
!6e!564!1K1k 1T8N<KCKGNITIk
!6f!564!:K6N1R/X/^1d6i:kAkEiIdL^LXIRENAK:K
!70!510!1K1z 1R6N:KAKENIRLXL^IdEiAk:k6i1d
!71!564!IKIz IRENAK:K6N1R/X/^1d6i:kAkEiId
!72!348!1K1k 1X4R8N<KCK
!73!510!GREN>K8K1N/R1V6XA[E^GbGdEi>k8k1i/d
!74!402!4<4b6i:k>k -K<K
!75!564!1K1b4i8k>kCiIb IKIk
!76!456!-K:k GK:k
!77!618!/K8k AK8k AKIk RKIk
!78!510!/KGk GK/k
!79!456!-K:k GK:k6s1x-z+z
!7a!510!GK/k /KGK /kGk
!20!300!
!3002!560!6b9b<c>e>h>k<m:o7o4n2l1i2f3d6b
!ff0c!520!7d<f<k5s
!3001!520!4e>p
!ff1f!640!5C:;D8L>KGDNAUA[ @hAi
!ff01!480!:8:[ :h:i
!ff1b!500!8N9N 7d<f<k5s
!ff1a!500!8N9N 8h9i
!300c!700![1I1IV
!300d!700!@B@h-h
!ff08!560!J-@=>L@[Jl
!ff09!560!3-==?L=[3l
!300a!640!J2:LJg X2ILXg
!300b!640!:2IL:g +2:L+g
!2014!1000!,LuL
!2026!1000!7L7M PLPM jLjM
!b7!500!<L<L
!ff5e!900!0N<GHJTPaNiH
"""##
}
