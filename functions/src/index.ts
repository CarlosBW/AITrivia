import * as admin from "firebase-admin";
import {setGlobalOptions} from "firebase-functions/v2";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

setGlobalOptions({maxInstances: 10});

admin.initializeApp();

export const finalizePvpMatch = onDocumentUpdated(
  "matches/{matchId}",
  async (event) => {
    const after = event.data?.after.data();

    if (!after) {
      return;
    }

    logger.info("Match updated", {
      matchId: event.params.matchId,
      status: after.status,
    });
  }
);
