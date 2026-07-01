Features:
Handles the "holding time" payments.
Uses a "Pull" instead of "Push" pattern. Instead of sending money to 20 people (expensive), it updates a balanceOf[player] mapping. Players then click "Claim" to withdraw their accumulated MON. This is much safer.
