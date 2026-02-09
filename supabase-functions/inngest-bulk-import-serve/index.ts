import { Inngest } from "https://esm.sh/inngest@3.22.0";
import { serve } from "https://esm.sh/inngest@3.22.0/edge";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";
import Papa from "https://esm.sh/papaparse@5.4.1";

const inngest = new Inngest({ id: "crm-bulk-import-system" });

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function getSupabase() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}

// Workflow: Bulk Import Purchases
const bulkImportPurchases = inngest.createFunction(
  {
    id: "bulk-import-purchases",
    timeout: "30m",  // Allow up to 30 minutes for large files
    retries: 1,      // Limited retries (already atomic)
  },
  { event: "import/bulk-purchases" },
  async ({ event, step }) => {
    const { 
      batch_id, 
      file_path, 
      merchant_id 
    } = event.data;
    
    const supabase = getSupabase();
    
    // Step 1: Update status to processing
    await step.run("update-status-processing", async () => {
      await supabase
        .from("bulk_import_batches")
        .update({ 
          status: "processing", 
          started_at: new Date().toISOString() 
        })
        .eq("id", batch_id);
      return { status: "processing" };
    });
    
    // Step 2: Read and parse CSV file
    const csvData = await step.run("parse-csv", async () => {
      const fileContent = await Deno.readTextFile(file_path);
      
      const parsed = Papa.parse(fileContent, {
        header: true,
        skipEmptyLines: true,
        transformHeader: (header: string) => header.trim().toLowerCase(),
      });
      
      if (parsed.errors.length > 0) {
        throw new Error(`CSV parsing errors: ${JSON.stringify(parsed.errors)}`);
      }
      
      return parsed.data;
    });
    
    // Step 3: Group rows by transaction_number
    const grouped = await step.run("group-by-transaction", async () => {
      const purchases: Record<string, any> = {};
      
      for (const row of csvData as any[]) {
        const txnNum = row.transaction_number;
        
        if (!purchases[txnNum]) {
          purchases[txnNum] = {
            transaction_number: txnNum,
            transaction_date: row.transaction_date,
            user_id: row.user_id,
            store_id: row.store_id || null,
            total_amount: parseFloat(row.final_amount), // Use final_amount as total
            discount_amount: parseFloat(row.discount_amount || 0),
            tax_amount: parseFloat(row.tax_amount || 0),
            final_amount: parseFloat(row.final_amount),
            status: row.status || "completed",
            payment_status: row.payment_status || "paid",
            record_type: row.record_type || "credit",
            processing_method: row.processing_method || "queue",
            earn_currency: row.earn_currency !== "false",
            transaction_source: row.transaction_source || "admin",
            external_ref: row.external_ref || null,
            notes: row.notes || null,
            items: [],
          };
        }
        
        // Add line item
        purchases[txnNum].items.push({
          sku_id: row.sku_id,
          quantity: parseFloat(row.quantity),
          unit_price: parseFloat(row.unit_price),
          discount_amount: parseFloat(row.item_discount_amount || 0),
          tax_amount: parseFloat(row.item_tax_amount || 0),
          line_total: parseFloat(row.line_total),
        });
      }
      
      return Object.values(purchases);
    });
    
    // Step 4: Validate all data
    await step.run("validate-data", async () => {
      const userIds = new Set(grouped.map((p: any) => p.user_id));
      const skuIds = new Set(
        grouped.flatMap((p: any) => p.items.map((i: any) => i.sku_id))
      );
      
      // Check all user_ids exist
      const { data: users } = await supabase
        .from("user_accounts")
        .select("id")
        .eq("merchant_id", merchant_id)
        .in("id", Array.from(userIds));
      
      if (users!.length !== userIds.size) {
        throw new Error(
          `Invalid user_ids found. Expected ${userIds.size}, found ${users!.length}`
        );
      }
      
      // Check all sku_ids exist
      const { data: skus } = await supabase
        .from("product_sku_master")
        .select("id")
        .in("id", Array.from(skuIds));
      
      if (skus!.length !== skuIds.size) {
        throw new Error(
          `Invalid sku_ids found. Expected ${skuIds.size}, found ${skus!.length}`
        );
      }
      
      return { validated: true };
    });
    
    // Step 5: Atomic insert via PostgreSQL function
    const result = await step.run("atomic-insert", async () => {
      const { data, error } = await supabase.rpc(
        "bulk_insert_purchases_with_items",
        {
          p_purchases: grouped,
          p_merchant_id: merchant_id,
        }
      );
      
      if (error) {
        throw new Error(`Database insert failed: ${error.message}`);
      }
      
      const [insertResult] = data as any[];
      
      if (!insertResult.success) {
        throw new Error(`Transaction failed: ${insertResult.error_message}`);
      }
      
      return {
        purchases: insertResult.imported_purchases,
        items: insertResult.imported_items,
      };
    });
    
    // Step 6: Update batch status to completed
    await step.run("update-status-completed", async () => {
      await supabase
        .from("bulk_import_batches")
        .update({
          status: "completed",
          imported_purchases: result.purchases,
          imported_items: result.items,
          completed_at: new Date().toISOString(),
        })
        .eq("id", batch_id);
      return { status: "completed" };
    });
    
    // Step 7: Delete temporary file
    await step.run("cleanup-file", async () => {
      try {
        await Deno.remove(file_path);
      } catch (e) {
        console.warn(`Failed to delete file ${file_path}:`, e);
      }
      return { cleaned: true };
    });
    
    return {
      success: true,
      batch_id,
      purchases_imported: result.purchases,
      items_imported: result.items,
    };
  }
);

// Error handler wrapper for purchases
const bulkImportPurchasesWithErrorHandling = inngest.createFunction(
  bulkImportPurchases.opts,
  bulkImportPurchases.trigger,
  async (context) => {
    try {
      return await bulkImportPurchases.fn(context);
    } catch (error) {
      const supabase = getSupabase();
      await supabase
        .from("bulk_import_batches")
        .update({
          status: "failed",
          error_message: error instanceof Error ? error.message : String(error),
          completed_at: new Date().toISOString(),
        })
        .eq("id", context.event.data.batch_id);
      throw error;
    }
  }
);

// Workflow: Bulk Import Customers (validate then insert, single RPC)
const bulkImportCustomers = inngest.createFunction(
  {
    id: "bulk-import-customers",
    timeout: "30m",
    retries: 1,
  },
  { event: "import/bulk-customers" },
  async ({ event, step }) => {
    const { batch_id, merchant_id, create_wallet_ledger_entry, csv_data } = event.data;
    const supabase = getSupabase();

    await step.run("update-status-processing", async () => {
      await supabase
        .from("bulk_import_batches")
        .update({ status: "processing", started_at: new Date().toISOString() })
        .eq("id", batch_id);
      return { status: "processing" };
    });

    const rows = csv_data as Record<string, unknown>[];

    const result = await step.run("validate-and-insert", async () => {
      const { data, error } = await supabase.rpc("bulk_upsert_customers_from_import", {
        p_rows: rows,
        p_merchant_id: merchant_id,
        p_create_wallet_ledger_entry: create_wallet_ledger_entry === true,
        p_batch_id: batch_id,
        p_max_errors: 100,
      });

      if (error) {
        throw new Error(`RPC failed: ${error.message}`);
      }

      const row = Array.isArray(data) ? data[0] : data;
      if (!row) {
        throw new Error("RPC returned no row");
      }

      return row as {
        success: boolean;
        valid: boolean;
        imported_count: number;
        updated_count: number;
        error_message: string | null;
        errors: { row: number; reason: string }[] | null;
        total_error_count: number;
      };
    });

    if (!result.success) {
      if (result.valid === false && result.errors) {
        await step.run("update-status-validation-failed", async () => {
          await supabase
            .from("bulk_import_batches")
            .update({
              status: "validation_failed",
              validation_errors: result.errors,
              metadata: { total_error_count: result.total_error_count },
              completed_at: new Date().toISOString(),
            })
            .eq("id", batch_id);
          return { status: "validation_failed" };
        });
        return {
          success: false,
          batch_id,
          valid: false,
          errors: result.errors,
          total_error_count: result.total_error_count,
        };
      }

      await step.run("update-status-failed", async () => {
        await supabase
          .from("bulk_import_batches")
          .update({
            status: "failed",
            error_message: result.error_message || "Insert failed",
            completed_at: new Date().toISOString(),
          })
          .eq("id", batch_id);
        return { status: "failed" };
      });
      return {
        success: false,
        batch_id,
        error_message: result.error_message,
      };
    }

    await step.run("update-status-completed", async () => {
      await supabase
        .from("bulk_import_batches")
        .update({
          status: "completed",
          imported_users: (result.imported_count ?? 0) + (result.updated_count ?? 0),
          completed_at: new Date().toISOString(),
        })
        .eq("id", batch_id);
      return { status: "completed" };
    });

    return {
      success: true,
      batch_id,
      imported_count: result.imported_count,
      updated_count: result.updated_count,
    };
  }
);

const bulkImportCustomersWithErrorHandling = inngest.createFunction(
  bulkImportCustomers.opts,
  bulkImportCustomers.trigger,
  async (context) => {
    try {
      return await bulkImportCustomers.fn(context);
    } catch (error) {
      const supabase = getSupabase();
      await supabase
        .from("bulk_import_batches")
        .update({
          status: "failed",
          error_message: error instanceof Error ? error.message : String(error),
          completed_at: new Date().toISOString(),
        })
        .eq("id", context.event.data.batch_id);
      throw error;
    }
  }
);

const handler = serve({
  client: inngest,
  functions: [bulkImportPurchasesWithErrorHandling, bulkImportCustomersWithErrorHandling],
  signingKey: Deno.env.get("INNGEST_SIGNING_KEY"),
  servePath: "/functions/v1/inngest-bulk-import-serve",
});

Deno.serve(async (req: Request) => {
  return await handler(req);
});
