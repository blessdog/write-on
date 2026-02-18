import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@13.0.0?target=deno";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, { apiVersion: "2023-10-16" });
const endpointSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  const signature = req.headers.get("stripe-signature");
  if (!signature) {
    return new Response("Missing signature", { status: 400 });
  }

  const body = await req.text();
  let event: Stripe.Event;

  try {
    event = await stripe.webhooks.constructEventAsync(body, signature, endpointSecret);
  } catch (err) {
    return new Response(`Webhook Error: ${err.message}`, { status: 400 });
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  switch (event.type) {
    case "checkout.session.completed": {
      const session = event.data.object as Stripe.Checkout.Session;
      const userId = session.client_reference_id;
      if (!userId) break;

      const update: Record<string, unknown> = {
        stripe_customer_id: session.customer as string,
      };

      if (session.mode === "subscription") {
        update.subscription = "pro";
        update.stripe_subscription_id = session.subscription as string;
        // Fetch subscription to get period end
        const sub = await stripe.subscriptions.retrieve(session.subscription as string);
        update.subscription_expires_at = new Date(sub.current_period_end * 1000).toISOString();
        update.monthly_minutes_limit = 999999;
      } else {
        // One-time payment = lifetime
        update.subscription = "lifetime";
        update.subscription_expires_at = null;
        update.monthly_minutes_limit = 999999;
      }

      await supabase.from("profiles").update(update).eq("id", userId);
      break;
    }

    case "customer.subscription.deleted": {
      const sub = event.data.object as Stripe.Subscription;
      const customerId = sub.customer as string;

      // Find user by stripe_customer_id
      const { data: profiles } = await supabase
        .from("profiles")
        .select("id")
        .eq("stripe_customer_id", customerId);

      if (profiles && profiles.length > 0) {
        await supabase
          .from("profiles")
          .update({
            subscription: "free",
            stripe_subscription_id: null,
            subscription_expires_at: null,
            monthly_minutes_limit: 15,
          })
          .eq("id", profiles[0].id);
      }
      break;
    }

    case "customer.subscription.updated": {
      const sub = event.data.object as Stripe.Subscription;
      const customerId = sub.customer as string;

      const { data: profiles } = await supabase
        .from("profiles")
        .select("id")
        .eq("stripe_customer_id", customerId);

      if (profiles && profiles.length > 0) {
        const isActive = sub.status === "active" || sub.status === "trialing";
        await supabase
          .from("profiles")
          .update({
            subscription: isActive ? "pro" : "free",
            subscription_expires_at: new Date(sub.current_period_end * 1000).toISOString(),
            monthly_minutes_limit: isActive ? 999999 : 15,
          })
          .eq("id", profiles[0].id);
      }
      break;
    }
  }

  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
