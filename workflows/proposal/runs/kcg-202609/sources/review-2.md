# Founder review — round 2 viewer page (2026-09-29) — verbatim

note for marketplace claim we natively integrate with shopee lazada tiktok already so can connect right away with no custom integration cost. for modern trade platfroms like macro pro we will develop integration free of charge

Actually, Makro Pro, we should integrate as another channel, like marketplace. Note: depending on the availability of the open API connection, if not, users can upload receipts.

You mentioned AI read receipt. here as a declaration that that's the default way but we should mention that we have two ways to approve a receipt. Once it's approved, what will happen, and then explain the two ways: manual is the default.

> AI reads every receipt: the chain and branch, receipt number, date and each line. It keeps only the lines on your product list for that chain and ignores the rest of the basket. The earnable amount is the value of those KCG lines after their discounts, and points follow your normal earn rules (§04). Product-based rules and missions, such as bonus points on a new SKU, work on receipts too.
>
> Manual approval is the default. Every receipt lands in your review queue already read: chain, branch, receipt number, total and the matched KCG lines are filled in, with the reason it needs a look. The reviewer checks the photo, corrects anything, and approves or rejects. The member hears on LINE when the receipt is received, approved or rejected. If you would rather not staff the queue, Rocket's Receipt Approval service can work it for you (TOR 11, §14).
>
> Auto approval is optional. When you switch it on, a clean receipt is approved on the spot and the member sees "approved, +N points". A receipt auto-approves only whe....

For POS earn, we did not mention at all the consume from email file method, which is actually the most convenient. The effect is the same as integration, but we do not need to do any integration, especially on the customer side.

> Your own store is where the programme pays back most: every order earns automatically with no claim, you keep the full margin, and you can make it the best place to earn. The slide below shows the pattern: marketplace orders earn at the base rate, your own store earns 25% more, and both land in one balance.

There are a lot of places like this that are not explained well. You should mention that one of the main objectives of the loyalty program is converting third-party to first-party. And the way to do so is to acquire them from a third party at a lower earn rate because you have low margin, and the user eventually converts on first party due to more favorable earn rates. We can do exactly that.

The "Earn from brand.com" section does not elaborate at all on the most important point, which is the difference between our Shopify plugin and normal order sync. I put this in the original prompt, as well as, I believe, in the workflow. We even have a slide for this, so why?

I feel the proposal is kind of low quality. A lot of AI slop, like writing patterns: "You own this, you keep this. Every order earns this," kind of thing. "The journey you design, and the one members take" Also, we're missing out on a lot of important information and not elaborating on it well. why?

The line "official account" section should not be in transaction capturing earn, but maybe in the join stages, right? Also, "every way to earn in one place" should be in the introduction of transaction capturing?? not at the end?

Lucky draw should be in the campaigns part, not reward and privilege, right?

For control on every reward, we should have a white frame scroll down to that section of the page for the conflict.
*(parent reading: an iframe of the live admin reward settings, opened scrolled down to the controls/config section)*

Why are activation, rule-based marketing, and AI decisioning all separate sections? They should all be in the same sections: rule-based marketing and AI decisioning in subsections.

Should Audience Builder and Targeted Line Broadcast be in another section that's not Activate? I'm not sure how to classify it. Please suggest, because Audience could be in Members, right, and Targeted Line Broadcast could be in Rule-Based Marketing? I don't know, but if Targeted Line Broadcast is in Rule-Based Marketing, we must distinguish clearly between the difference between workflows and Targeted Line Broadcast.

> A member who earned points on Shopee, at Lotus's or at your flagship store can spend them on your own online store, and earns more when they buy there. That one wallet is what turns a third-party buyer into a customer of your own store. Rocket's Shopify plugin is live today and ready the day your Shopify store opens (TOR 3.4, 7.10, 8.6). You don't rebuild anything: the members, balances, tiers and rewards are the ones you already run in LINE. It is Thailand's only Shopify-native loyalty plugin, built and run by Rocket and listed on the Shopify App Store as 1to1.

I feel this part is not very well explained, and it should be clearer that there are different dimensions: earn, burn, see, and refer, and that, for most normal integrations, it cannot do. What's the difference

> First order on a third-party channel, next order on your own store: one member balance across LINE and Shopify
> First order on a third-party channel, next order on your own store: one member balance across LINE and Shopify
> Whole slide from the KCG pitch deck (kcg-loyalty-crm), slide id loyalty.line-shopify-flow. Members join and earn in the LINE web app
> Order sync vs the Rocket Shopify plugin
> When loyalty vendors say they "integrate with Shopify", they usually mean order sync: store orders are sent to the loyalty system and become points. Order sync brings Shopify into your loyalty programme. The plugin brings your loyalty programme into Shopify.

in the Rocket AI section, you should mention that, throughout the proposal so far, there may be mentions of AI embedded in different sections. This is a summary of our AI layer, which could be thought of as a common substrate that makes everything flow

I feel that, because perhaps each section is written separately, there's not a good flow between the sections (one leading to another, references to other parts, etc.). I think we should review the whole proposal holistically again for flow
